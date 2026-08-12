import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/invoice.dart';
import '../providers/business_profile_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/database_provider.dart';
import '../providers/invoice_provider.dart';
import '../screens/create_invoice_screen.dart';
import '../screens/pdf_preview_screen.dart';
import '../screens/tax_report_screen.dart';
import '../screens/expenses_screen.dart';
import '../screens/add_expense_screen.dart';
import '../screens/all_invoices_screen.dart';
import '../services/app_database.dart';
import '../services/tax_engine.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/glass_card.dart';
import '../widgets/invoice_tile.dart';

/// The main dashboard screen shown after launch.
///
/// Displays an estimated available balance, quick-action buttons,
/// and the three most recent invoices.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Stack(
        children: [
          // ── Background glow orbs (purely decorative) ──────────────────────
          const _BackgroundOrbs(),

          // ── Main scrollable content ───────────────────────────────────────
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: 12),
                      _Header(userName: profile.name),
                      const SizedBox(height: 32),
                      const _BalanceCard(),
                      const SizedBox(height: 24),
                      const _ActionButtons(),
                      const SizedBox(height: 36),
                      _SectionHeader(
                        title: 'Recent invoices',
                        onViewAll: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AllInvoicesScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _RecentInvoicesList(),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _showEstimateInfo(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXL),
          ),
          border: Border(
            top: BorderSide(color: AppTheme.glassBorder, width: 1.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Estimated available', style: AppTheme.headlineMedium()),
            const SizedBox(height: 10),
            Text(
              'This estimate uses only paid income, your configured tax rate, and expenses tracked in the app. It is not a bank balance or tax advice.',
              style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 18),
            Text(
              'Income − reserved taxes − tracked expenses',
              style: AppTheme.bodyLarge(color: AppTheme.emerald),
            ),
          ],
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Background decorative orbs
// ══════════════════════════════════════════════════════════════════════════════

class _BackgroundOrbs extends StatelessWidget {
  const _BackgroundOrbs();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SizedBox.expand(
      child: Stack(
        children: [
          // Top-right emerald orb
          Positioned(
            top: -80,
            right: -60,
            child: _Orb(
              size: size.width * 0.7,
              color: AppTheme.emerald.withAlpha(18),
            ),
          ),
          // Mid-left purple orb
          Positioned(
            top: size.height * 0.35,
            left: -size.width * 0.25,
            child: _Orb(
              size: size.width * 0.6,
              color: const Color(0xFF6C63FF).withAlpha(14),
            ),
          ),
          // Bottom-right subtle glow
          Positioned(
            bottom: -40,
            right: -40,
            child: _Orb(
              size: size.width * 0.5,
              color: AppTheme.emerald.withAlpha(10),
            ),
          ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Header
// ══════════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  const _Header({required this.userName});
  final String userName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Greeting text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting(), style: AppTheme.bodyMedium()),
              const SizedBox(height: 2),
              Text(userName, style: AppTheme.headlineMedium()),
            ],
          ),
        ),
      ],
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Glassmorphic Balance Card
// ══════════════════════════════════════════════════════════════════════════════

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdownAsync = ref.watch(taxBreakdownProvider);

    return breakdownAsync.when(
      data: (b) => _BalanceCardContent(breakdown: b),
      loading: () => const _BalanceCardShimmer(),
      error: (e, _) => _BalanceCardError(message: e.toString()),
    );
  }
}

class _BalanceCardContent extends ConsumerWidget {
  const _BalanceCardContent({required this.breakdown});
  final TaxBreakdown breakdown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencySymbolProvider);
    final currencyCode = ref.watch(currencyCodeProvider);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        // Outer emerald glow
        boxShadow: [
          BoxShadow(
            color: AppTheme.emerald.withAlpha(35),
            blurRadius: 40,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: GlassCard(
        padding: const EdgeInsets.all(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x22FFFFFF), Color(0x08FFFFFF)],
        ),
        border: Border.all(color: AppTheme.emerald.withAlpha(50), width: 1.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Label ─────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.emerald.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.emerald,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'ESTIMATED AVAILABLE',
                        style: AppTheme.labelSmall(color: AppTheme.emerald),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'About estimated available',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(
                    Icons.info_outline_rounded,
                    color: AppTheme.emerald.withAlpha(190),
                    size: 20,
                  ),
                  onPressed: () => _showEstimateInfo(context),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Big amount ────────────────────────────────────────────────
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatCurrency(
                  breakdown.safeToSpend,
                  currency,
                  currencyCode: currencyCode,
                ),
                style: AppTheme.displayLarge(color: AppTheme.textPrimary),
              ),
            ),

            const SizedBox(height: 6),
            Text(
              'Income − reserved taxes − tracked expenses',
              style: AppTheme.bodyMedium(),
            ),

            const SizedBox(height: 28),

            // ── Divider ───────────────────────────────────────────────────
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withAlpha(30),
                    Colors.white.withAlpha(5),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 22),

            // ── Stat row ──────────────────────────────────────────────────
            Row(
              children: [
                _StatItem(
                  label: 'Income',
                  value: formatCurrency(
                    breakdown.totalRevenue,
                    currency,
                    currencyCode: currencyCode,
                  ),
                  icon: Icons.trending_up_rounded,
                  iconColor: AppTheme.emerald,
                ),
                _VerticalDivider(),
                _StatItem(
                  label: 'Taxes',
                  value: formatCurrency(
                    breakdown.taxReserved,
                    currency,
                    currencyCode: currencyCode,
                  ),
                  icon: Icons.account_balance_outlined,
                  iconColor: AppTheme.warningAmber,
                ),
                _VerticalDivider(),
                _StatItem(
                  label: 'Expenses',
                  value: formatCurrency(
                    breakdown.expenses,
                    currency,
                    currencyCode: currencyCode,
                  ),
                  icon: Icons.receipt_long_outlined,
                  iconColor: AppTheme.errorRed,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ExpensesScreen()),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  value,
                  style: AppTheme.bodyMedium(
                    color: AppTheme.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTheme.labelSmall(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 40, width: 1, color: AppTheme.glassBorder);
  }
}

class _BalanceCardShimmer extends StatelessWidget {
  const _BalanceCardShimmer();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(
            color: AppTheme.emerald,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

class _BalanceCardError extends StatelessWidget {
  const _BalanceCardError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 32),
          const SizedBox(height: 8),
          Text(message, style: AppTheme.bodyMedium(color: AppTheme.errorRed)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Action Buttons
// ══════════════════════════════════════════════════════════════════════════════

class _ActionButtons extends StatelessWidget {
  const _ActionButtons();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.65,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _ActionButton(
          label: 'Invoice',
          subtitle: 'New',
          icon: Icons.receipt_long_rounded,
          accentColor: AppTheme.emerald,
          glowColor: AppTheme.emeraldGlow,
          isPrimary: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreateInvoiceScreen(isQuote: false),
            ),
          ),
        ),
        _ActionButton(
          label: 'Quote',
          subtitle: 'New',
          icon: Icons.request_quote_rounded,
          accentColor: AppTheme.electricBlue,
          glowColor: AppTheme.electricBlue.withAlpha(80),
          isPrimary: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreateInvoiceScreen(isQuote: true),
            ),
          ),
        ),
        _ActionButton(
          label: 'Expense',
          subtitle: 'Add',
          icon: Icons.receipt_long_rounded,
          accentColor: AppTheme.warningAmber,
          glowColor: AppTheme.warningAmber.withAlpha(70),
          isPrimary: false,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AddExpenseScreen())),
        ),
        _ActionButton(
          label: 'Tax',
          subtitle: 'Report',
          icon: Icons.bar_chart_rounded,
          accentColor: AppTheme.electricBlue,
          glowColor: AppTheme.electricBlue.withAlpha(70),
          isPrimary: false,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TaxReportScreen())),
        ),
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.glowColor,
    required this.isPrimary,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Color glowColor;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 0.04,
    );
    _scale = Tween(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 100,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.accentColor.withAlpha(15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.accentColor.withAlpha(40),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Icon block
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.accentColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(widget.icon, color: widget.accentColor, size: 18),
                ),
              ),
              // Text
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.subtitle.toUpperCase(),
                    style: AppTheme.labelSmall(color: widget.accentColor)
                        .copyWith(
                          fontSize: 9,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.label,
                    style: AppTheme.bodyMedium(
                      color: AppTheme.textPrimary,
                    ).copyWith(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Section header
// ══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onViewAll});
  final String title;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: AppTheme.titleLarge()),
        const Spacer(),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              'View all',
              style: AppTheme.bodyMedium(color: AppTheme.emerald),
            ),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Recent Invoices List
// ══════════════════════════════════════════════════════════════════════════════

class _RecentInvoicesList extends ConsumerStatefulWidget {
  const _RecentInvoicesList();

  @override
  ConsumerState<_RecentInvoicesList> createState() =>
      _RecentInvoicesListState();
}

class _RecentInvoicesListState extends ConsumerState<_RecentInvoicesList> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoiceListProvider);

    return invoicesAsync.when(
      data: (invoices) {
        if (invoices.isEmpty) return const _EmptyInvoicesState();

        final filtered = invoices.where((inv) {
          if (_selectedFilter == 'All') return true;
          if (_selectedFilter == 'Pending') {
            return inv.status == InvoiceStatus.pending &&
                inv.documentType != 'quote';
          }
          if (_selectedFilter == 'Paid') {
            return inv.status == InvoiceStatus.paid &&
                inv.documentType != 'quote';
          }
          if (_selectedFilter == 'Overdue') {
            return inv.status == InvoiceStatus.overdue &&
                inv.documentType != 'quote';
          }
          if (_selectedFilter == 'Quote') return inv.documentType == 'quote';
          return true;
        }).toList();

        final recent = filtered.take(5).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Filter Chips Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  _filterChip(
                    'All',
                    Icons.grid_view_rounded,
                    _selectedFilter == 'All',
                    AppTheme.emerald,
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    'Pending',
                    Icons.schedule_rounded,
                    _selectedFilter == 'Pending',
                    AppTheme.warningAmber,
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    'Paid',
                    Icons.check_circle_rounded,
                    _selectedFilter == 'Paid',
                    AppTheme.emerald,
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    'Overdue',
                    Icons.error_outline_rounded,
                    _selectedFilter == 'Overdue',
                    AppTheme.errorRed,
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    'Quote',
                    Icons.request_quote_rounded,
                    _selectedFilter == 'Quote',
                    AppTheme.electricBlue,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No $_selectedFilter items found',
                    style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              for (final inv in recent)
                InvoiceTile(
                  invoice: inv,
                  onTap: () => _showInvoiceActionSheet(context, ref, inv),
                ),
          ],
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: CircularProgressIndicator(
            color: AppTheme.emerald,
            strokeWidth: 2,
          ),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Failed to load invoices: $e',
          style: AppTheme.bodyMedium(color: AppTheme.errorRed),
        ),
      ),
    );
  }

  Widget _filterChip(
    String label,
    IconData icon,
    bool isSelected,
    Color activeColor,
  ) {
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    activeColor.withAlpha(55),
                    activeColor.withAlpha(20),
                  ],
                )
              : null,
          color: isSelected ? null : Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : AppTheme.glassBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withAlpha(35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? activeColor : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style:
                  AppTheme.labelSmall(
                    color: isSelected ? activeColor : AppTheme.textSecondary,
                  ).copyWith(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInvoiceActionSheet(
    BuildContext context,
    WidgetRef ref,
    Invoice invoice,
  ) async {
    final db = ref.read(databaseServiceProvider);
    final client = await db.getClientById(invoice.clientId);
    final clientName = client?.name ?? 'Client #${invoice.clientId}';

    final currency = ref.read(currencySymbolProvider);
    final currencyCode = ref.read(currencyCodeProvider);

    if (!context.mounted) return;

    var selectedStatus = invoice.status;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radiusXL),
                ),
                border: Border(
                  top: BorderSide(color: AppTheme.glassBorder, width: 1.5),
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Invoice Number, Price, and Circular 'X' Close Button
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              invoice.invoiceNumber,
                              style: AppTheme.titleLarge(),
                            ),
                            const SizedBox(height: 2),
                            Text(clientName, style: AppTheme.bodyMedium()),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            formatCurrency(
                              invoice.totalAmount,
                              currency,
                              currencyCode: currencyCode,
                            ),
                            style: AppTheme.displayLarge(
                              color: AppTheme.emerald,
                            ).copyWith(fontSize: 22),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Circular 'X' Close Button
                      GestureDetector(
                        onTap: () => Navigator.of(modalContext).pop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.bgSurface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.glassBorder),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: AppTheme.textSecondary,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Status Selector Label
                  Text('UPDATE INVOICE STATUS', style: AppTheme.labelSmall()),
                  const SizedBox(height: 12),

                  // Status buttons row [Pending, Paid, Overdue]
                  Row(
                    children: InvoiceStatus.values.map((status) {
                      final isSelected = selectedStatus == status;
                      final (color, label) = switch (status) {
                        InvoiceStatus.paid => (AppTheme.emerald, 'PAID'),
                        InvoiceStatus.pending => (
                          AppTheme.warningAmber,
                          'PENDING',
                        ),
                        InvoiceStatus.overdue => (AppTheme.errorRed, 'OVERDUE'),
                        InvoiceStatus.draft => (
                          AppTheme.textSecondary,
                          'DRAFT',
                        ),
                        InvoiceStatus.cancelled => (
                          AppTheme.errorRed,
                          'CANCELLED',
                        ),
                        InvoiceStatus.none => (
                          AppTheme.textSecondary,
                          'UNSPECIFIED',
                        ),
                      };

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () async {
                              setModalState(() {
                                selectedStatus = status;
                              });

                              // Immediately update status in database (sheet stays open)
                              await ref
                                  .read(invoiceActionsProvider)
                                  .updateInvoiceStatus(invoice.id, status);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withAlpha(40)
                                    : AppTheme.bgSurface,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSM,
                                ),
                                border: Border.all(
                                  color: isSelected
                                      ? color
                                      : AppTheme.glassBorder,
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    color: isSelected
                                        ? color
                                        : AppTheme.textHint,
                                    size: 18,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    label,
                                    style: AppTheme.labelSmall(
                                      color: isSelected
                                          ? color
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons: Edit Invoice & Preview PDF
                  Row(
                    children: [
                      // Edit Invoice Button
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: AppTheme.bgSurface,
                              foregroundColor: AppTheme.textPrimary,
                              side: const BorderSide(
                                color: AppTheme.glassBorder,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMD,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: AppTheme.emerald,
                              size: 18,
                            ),
                            label: Text(
                              'Edit Invoice',
                              style: AppTheme.bodyMedium(),
                            ),
                            onPressed: () {
                              Navigator.of(modalContext).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CreateInvoiceScreen(
                                    existingInvoice: invoice,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // PDF Preview & Export Button
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.bgSurface,
                              foregroundColor: AppTheme.textPrimary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMD,
                                ),
                                side: const BorderSide(
                                  color: AppTheme.glassBorder,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.remove_red_eye_outlined,
                              color: AppTheme.emerald,
                              size: 18,
                            ),
                            label: Text(
                              'Preview & Export',
                              style: AppTheme.bodyMedium(),
                            ),
                            onPressed: () async {
                              final items = await db.getItemsForInvoice(
                                invoice.id,
                              );
                              final targetClient =
                                  client ??
                                  Client(
                                    id: invoice.clientId,
                                    name: 'Client #${invoice.clientId}',
                                  );
                              if (modalContext.mounted) {
                                Navigator.of(modalContext).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => PdfPreviewScreen(
                                      invoice: invoice,
                                      client: targetClient,
                                      items: items,
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (invoice.documentType == 'quote') ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.emerald,
                          foregroundColor: AppTheme.bgDeep,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMD,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.transform_rounded, size: 20),
                        label: Text(
                          'Convert quote to invoice',
                          style: AppTheme.bodyLarge(color: AppTheme.bgDeep),
                        ),
                        onPressed: () async {
                          final nextInvNo = await ref
                              .read(invoiceActionsProvider)
                              .generateInvoiceNumber(prefix: 'INV');

                          final updatedEntry = InvoicesCompanion(
                            id: Value(invoice.id),
                            invoiceNumber: Value(nextInvNo),
                            documentType: const Value('invoice'),
                          );

                          await ref
                              .read(invoiceActionsProvider)
                              .updateInvoice(updatedEntry);

                          if (!modalContext.mounted) return;
                          Navigator.of(modalContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppTheme.emerald,
                              content: Text(
                                'Quote converted to invoice $nextInvNo.',
                                style: AppTheme.bodyMedium(
                                  color: AppTheme.bgDeep,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyInvoicesState extends StatelessWidget {
  const _EmptyInvoicesState();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          // Placeholder icon inside a glowing circle
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.emerald.withAlpha(18),
              border: Border.all(
                color: AppTheme.emerald.withAlpha(50),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: AppTheme.emerald,
              size: 32,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Create your first invoice in seconds',
            style: AppTheme.titleLarge(),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep client details, line items, tax, and payment information in one place.',
            style: AppTheme.bodyMedium(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Mini CTA button
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateInvoiceScreen()),
              );
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                gradient: AppTheme.emeraldGradient,
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                boxShadow: [
                  BoxShadow(color: AppTheme.emeraldGlow, blurRadius: 14),
                ],
              ),
              child: Text(
                'Create Invoice',
                style: AppTheme.bodyLarge(color: AppTheme.bgDeep),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
