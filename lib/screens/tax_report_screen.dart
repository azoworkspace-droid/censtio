import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/invoice.dart';
import '../providers/currency_provider.dart';
import '../providers/entitlement_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/invoice_provider.dart';
import '../screens/paywall_screen.dart';
import '../services/app_database.dart';
import '../services/revenuecat_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/glass_card.dart';
import '../widgets/invoice_tile.dart';

/// Screen displaying basic tax & income stats for free users,
/// and unlocked quarterly breakdown & CPA-ready PDF export for Pro users.
class TaxReportScreen extends ConsumerStatefulWidget {
  const TaxReportScreen({super.key});

  @override
  ConsumerState<TaxReportScreen> createState() => _TaxReportScreenState();
}

class _TaxReportScreenState extends ConsumerState<TaxReportScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(keepScrollOffset: false);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final currency = ref.watch(currencySymbolProvider);
    final invoicesAsync = ref.watch(invoiceListProvider);
    final expensesAsync = ref.watch(expenseListProvider);
    final proAsync = ref.watch(entitlementProvider);
    final isPro = proAsync.value ?? false;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Tax & Income Report', style: AppTheme.titleLarge()),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.glassBorder),
        ),
      ),
      body: SafeArea(
        child: (invoicesAsync is AsyncLoading || expensesAsync is AsyncLoading)
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.emerald,
                  strokeWidth: 2.5,
                ),
              )
            : (invoicesAsync.hasError || expensesAsync.hasError)
            ? Center(
                child: Text(
                  'Error loading report: ${invoicesAsync.error ?? expensesAsync.error}',
                  style: AppTheme.bodyMedium(color: AppTheme.errorRed),
                ),
              )
            : _buildContent(
                context,
                ref,
                invoicesAsync.value ?? [],
                expensesAsync.value ?? [],
                currency,
                isPro,
              ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<Invoice> invoices,
    List<Expense> expenses,
    String currency,
    bool isPro,
  ) {
    // Only paid invoices contribute to confirmed revenue and tax reserves
    final paidInvoices = invoices
        .where((inv) => inv.status == InvoiceStatus.paid)
        .toList();

    final totalRevenue = paidInvoices.fold<double>(
      0.0,
      (sum, inv) => sum + inv.totalAmount,
    );

    final totalTaxCollected = paidInvoices.fold<double>(
      0.0,
      (sum, inv) => sum + (inv.totalAmount * (inv.taxRate / 100)),
    );

    final totalExpenses = expenses.fold<double>(
      0.0,
      (sum, e) => sum + e.amount,
    );

    final netProfit = totalRevenue - totalTaxCollected - totalExpenses;

    final totalInvoicesCount = paidInvoices.length;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      children: [
        // ── Free Summary Header Card ───────────────────────────────────────
        Text('OVERVIEW', style: AppTheme.labelSmall(color: AppTheme.emerald)),
        const SizedBox(height: 12),

        // Total Revenue Card
        GlassCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Confirmed Revenue', style: AppTheme.bodyMedium()),
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
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: AppTheme.emerald,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$totalInvoicesCount Paid',
                          style: AppTheme.labelSmall(color: AppTheme.emerald),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatCurrency(totalRevenue, currency),
                  style: AppTheme.displayLarge(color: AppTheme.emerald),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Based on settled paid invoices',
                style: AppTheme.bodyMedium(color: AppTheme.textHint),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Grid for Tax Collected & Total Paid Invoices
        Row(
          children: [
            // Tax Collected Card
            Expanded(
              child: GlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.account_balance_outlined,
                          size: 18,
                          color: AppTheme.warningAmber,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tax Reserved',
                            style: AppTheme.labelSmall(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatCurrency(totalTaxCollected, currency),
                        style: AppTheme.titleLarge(
                          color: AppTheme.warningAmber,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Invoices Count Card
            Expanded(
              child: GlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.receipt_long_rounded,
                          size: 18,
                          color: AppTheme.electricBlue,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Total Expenses',
                            style: AppTheme.labelSmall(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatCurrency(totalExpenses, currency),
                        style: AppTheme.titleLarge(color: AppTheme.errorRed),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Net Profit', style: AppTheme.bodyMedium()),
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: AppTheme.electricBlue,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatCurrency(netProfit, currency),
                  style: AppTheme.displayLarge(color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 36),

        // ── Conditional rendering: Pro Dashboard vs Upsell Section ───────
        if (isPro)
          _buildProDashboard(
            context,
            ref,
            invoices,
            expenses,
            currency,
            totalRevenue,
            totalTaxCollected,
            totalExpenses,
            paidInvoices,
          )
        else
          _buildUpsellSection(context),
      ],
    );
  }

  Widget _buildProDashboard(
    BuildContext context,
    WidgetRef ref,
    List<Invoice> invoices,
    List<Expense> expenses,
    String currency,
    double totalRevenue,
    double totalTaxCollected,
    double totalExpenses,
    List<Invoice> paidInvoices,
  ) {
    if (paidInvoices.isEmpty && expenses.isEmpty) {
      return _buildEmptyReportState(context);
    }

    // Group invoices by quarter
    double q1Rev = 0, q1Tax = 0, q1Exp = 0;
    double q2Rev = 0, q2Tax = 0, q2Exp = 0;
    double q3Rev = 0, q3Tax = 0, q3Exp = 0;
    double q4Rev = 0, q4Tax = 0, q4Exp = 0;

    for (final inv in paidInvoices) {
      final month = inv.date.month;
      final tax = inv.totalAmount * (inv.taxRate / 100);
      if (month >= 1 && month <= 3) {
        q1Rev += inv.totalAmount;
        q1Tax += tax;
      } else if (month >= 4 && month <= 6) {
        q2Rev += inv.totalAmount;
        q2Tax += tax;
      } else if (month >= 7 && month <= 9) {
        q3Rev += inv.totalAmount;
        q3Tax += tax;
      } else {
        q4Rev += inv.totalAmount;
        q4Tax += tax;
      }
    }

    for (final exp in expenses) {
      final month = exp.date.month;
      if (month >= 1 && month <= 3) {
        q1Exp += exp.amount;
      } else if (month >= 4 && month <= 6) {
        q2Exp += exp.amount;
      } else if (month >= 7 && month <= 9) {
        q3Exp += exp.amount;
      } else {
        q4Exp += exp.amount;
      }
    }

    final quarters = [
      {
        'quarter': 1,
        'name': 'Q1 (Jan - Mar)',
        'revenue': q1Rev,
        'tax': q1Tax,
        'expense': q1Exp,
      },
      {
        'quarter': 2,
        'name': 'Q2 (Apr - Jun)',
        'revenue': q2Rev,
        'tax': q2Tax,
        'expense': q2Exp,
      },
      {
        'quarter': 3,
        'name': 'Q3 (Jul - Sep)',
        'revenue': q3Rev,
        'tax': q3Tax,
        'expense': q3Exp,
      },
      {
        'quarter': 4,
        'name': 'Q4 (Oct - Dec)',
        'revenue': q4Rev,
        'tax': q4Tax,
        'expense': q4Exp,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Quarterly Breakdown', style: AppTheme.titleLarge()),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.emerald.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.emerald.withAlpha(80)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('👑 ', style: TextStyle(fontSize: 12)),
                  Text(
                    'PRO UNLOCKED',
                    style: AppTheme.labelSmall(color: AppTheme.emerald),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Quarterly List
        for (final q in quarters) ...[
          GestureDetector(
            onTap: () {
              final qNum = q['quarter'] as int;
              final qInvoices = _getInvoicesForQuarter(paidInvoices, qNum);
              _showQuarterInvoices(
                context,
                q['name'] as String,
                qInvoices,
                currency,
              );
            },
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        q['name'] as String,
                        style: AppTheme.bodyLarge().copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.touch_app_outlined,
                        size: 14,
                        color: AppTheme.emerald,
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppTheme.textHint,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _qStat(
                        'Revenue',
                        q['revenue'] as double,
                        AppTheme.emerald,
                        currency,
                      ),
                      _qStat(
                        'Expenses',
                        q['expense'] as double,
                        AppTheme.errorRed,
                        currency,
                      ),
                      _qStat(
                        'Tax Reserved',
                        q['tax'] as double,
                        AppTheme.warningAmber,
                        currency,
                      ),
                      _qStat(
                        'Net',
                        (q['revenue'] as double) -
                            (q['expense'] as double) -
                            (q['tax'] as double),
                        AppTheme.textPrimary,
                        currency,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        const SizedBox(height: 28),

        // Prominent Button: "📄 Export CPA-ready PDF"
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emerald,
              foregroundColor: AppTheme.bgDeep,
              elevation: 8,
              shadowColor: AppTheme.emeraldGlow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              ),
            ),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 22),
            label: Text(
              'Export CPA-ready PDF',
              style: AppTheme.titleLarge(color: AppTheme.bgDeep),
            ),
            onPressed: () async {
              await _exportTaxReportPdf(
                totalRevenue: totalRevenue,
                totalTaxCollected: totalTaxCollected,
                totalExpenses: totalExpenses,
                currency: currency,
                quarters: quarters,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyReportState(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.electricBlue.withAlpha(24),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.electricBlue.withAlpha(90)),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: AppTheme.electricBlue,
              size: 26,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your report is ready when you are.',
            style: AppTheme.titleLarge(),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a paid invoice or track an expense to see your income, taxes, and quarterly breakdown here.',
            style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 18),
          Text(
            'No report data yet',
            style: AppTheme.labelSmall(color: AppTheme.textHint),
          ),
        ],
      ),
    );
  }

  Widget _qStat(String label, double value, Color color, String currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.labelSmall(color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(
          formatCurrency(value, currency),
          style: AppTheme.bodyLarge().copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildUpsellSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.emerald.withAlpha(20),
            const Color(0xFF6C63FF).withAlpha(15),
            AppTheme.bgSurface,
          ],
        ),
        border: Border.all(color: AppTheme.emerald.withAlpha(80), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.emerald.withAlpha(20),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.emerald.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: AppTheme.emerald,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Advanced Reports & Export',
                        style: AppTheme.titleLarge(),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Unlock automated tax filing & analytics',
                        style: AppTheme.bodyMedium(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: AppTheme.glassBorder),
            const SizedBox(height: 16),

            // Locked Feature Items
            _featureRow('• Quarterly PDF Exports'),
            const SizedBox(height: 10),
            _featureRow('• Expense Tracking & Deductions'),
            const SizedBox(height: 10),
            _featureRow('• CPA-ready Breakdowns'),
            const SizedBox(height: 10),
            _featureRow('• Multi-Currency Tax Audit History'),

            const SizedBox(height: 28),

            // Upgrade Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.emerald,
                  foregroundColor: AppTheme.bgDeep,
                  elevation: 8,
                  shadowColor: AppTheme.emeraldGlow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  ),
                ),
                onPressed: () async {
                  final isPro = await RevenueCatService.isProUser();
                  if (!context.mounted) return;

                  if (!isPro) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PaywallScreen()),
                    );
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('👑 ', style: TextStyle(fontSize: 18)),
                    Text(
                      'Unlock Tax Reports - Pro',
                      style: AppTheme.titleLarge(color: AppTheme.bgDeep),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(String title) {
    return Row(
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          size: 18,
          color: AppTheme.emerald,
        ),
        const SizedBox(width: 10),
        Text(title, style: AppTheme.bodyLarge(color: AppTheme.textPrimary)),
      ],
    );
  }

  Future<void> _exportTaxReportPdf({
    required double totalRevenue,
    required double totalTaxCollected,
    required double totalExpenses,
    required String currency,
    required List<Map<String, dynamic>> quarters,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(18),
                decoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF111827),
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'ANNUAL TAX & INCOME REPORT',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFF00C896),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'CPA-Ready Audit Summary • Year ${DateTime.now().year}',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey400,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Summary Box
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _pdfStatBox(
                      'Total Revenue',
                      totalRevenue,
                      currency,
                      PdfColor.fromInt(0xFF00C896),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: _pdfStatBox(
                      'Total Expenses',
                      totalExpenses,
                      currency,
                      PdfColors.red400,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: _pdfStatBox(
                      'Tax Reserved',
                      totalTaxCollected,
                      currency,
                      PdfColor.fromInt(0xFFD97706),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: _pdfStatBox(
                      'Net Profit',
                      totalRevenue - totalExpenses - totalTaxCollected,
                      currency,
                      PdfColors.black,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 28),

              // Quarterly Breakdown Header
              pw.Text(
                'Quarterly Breakdown',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),

              // Table
              pw.TableHelper.fromTextArray(
                headers: [
                  'Quarter',
                  'Revenue',
                  'Expenses',
                  'Tax Reserved',
                  'Net',
                ],
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF111827),
                ),
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  ),
                ),
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                data: quarters
                    .map(
                      (q) => [
                        q['name'],
                        formatCurrency(q['revenue'] as double, currency),
                        formatCurrency(q['expense'] as double, currency),
                        formatCurrency(q['tax'] as double, currency),
                        formatCurrency(
                          (q['revenue'] as double) -
                              (q['expense'] as double) -
                              (q['tax'] as double),
                          currency,
                        ),
                      ],
                    )
                    .toList(),
              ),

              pw.Spacer(),

              // Footer
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated by Centsio AI: Invoice Maker',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.Text(
                    'Confidential CPA Report',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Tax_Report_${DateTime.now().year}.pdf',
    );
  }

  pw.Widget _pdfStatBox(
    String label,
    double value,
    String currency,
    PdfColor color,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            formatCurrency(value, currency),
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  List<Invoice> _getInvoicesForQuarter(List<Invoice> invoices, int quarter) {
    return invoices.where((inv) {
      if (inv.status != InvoiceStatus.paid) return false;
      final month = inv.date.month;
      if (quarter == 1) return month >= 1 && month <= 3;
      if (quarter == 2) return month >= 4 && month <= 6;
      if (quarter == 3) return month >= 7 && month <= 9;
      if (quarter == 4) return month >= 10 && month <= 12;
      return false;
    }).toList();
  }

  void _showQuarterInvoices(
    BuildContext context,
    String title,
    List<Invoice> quarterInvoices,
    String currency,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
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
            children: [
              // Drag Handle
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Header Title & Count Badge
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTheme.titleLarge()),
                        const SizedBox(height: 2),
                        Text(
                          'Paid Invoices Drill-down',
                          style: AppTheme.bodyMedium(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withAlpha(25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.emerald.withAlpha(80),
                        ),
                      ),
                      child: Text(
                        '${quarterInvoices.length} Paid',
                        style: AppTheme.labelSmall(color: AppTheme.emerald),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.glassBorder),

              // Body List / Empty State
              Expanded(
                child: quarterInvoices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.receipt_long_outlined,
                              size: 48,
                              color: AppTheme.textHint,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No paid invoices in this quarter.',
                              style: AppTheme.bodyLarge(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: quarterInvoices.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final inv = quarterInvoices[index];
                          return InvoiceTile(invoice: inv);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
