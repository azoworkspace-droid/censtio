import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/invoice.dart';
import '../providers/currency_provider.dart';
import '../providers/database_provider.dart';
import '../providers/invoice_provider.dart';
import '../screens/create_invoice_screen.dart';
import '../screens/pdf_preview_screen.dart';
import '../screens/paywall_screen.dart';
import '../services/app_database.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/glass_card.dart';
import '../widgets/invoice_tile.dart';

/// Screen listing all created invoices in the database with Payment Method filtering.
class AllInvoicesScreen extends ConsumerStatefulWidget {
  const AllInvoicesScreen({super.key});

  @override
  ConsumerState<AllInvoicesScreen> createState() => _AllInvoicesScreenState();
}

class _AllInvoicesScreenState extends ConsumerState<AllInvoicesScreen> {
  String _statusFilter = 'All';
  String _paymentMethodFilter = 'All';
  String _sortBy = 'Newest';
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _searchController = TextEditingController();
  final Map<int, String> _clientNames = <int, String>{};

  final List<String> _statusOptions = const [
    'All',
    'Draft',
    'Pending',
    'Paid',
    'Overdue',
    'Cancelled',
  ];
  final List<String> _paymentMethodOptions = const [
    'All',
    'Bank Transfer',
    'Cash',
    'Check',
    'Credit Card',
    'Other',
  ];
  final List<String> _sortOptions = const [
    'Newest',
    'Oldest',
    'Highest Amount',
    'Client',
  ];

  @override
  void initState() {
    super.initState();
    _loadClientNames();
  }

  Future<void> _loadClientNames() async {
    final clients = await ref.read(databaseServiceProvider).getAllClients();
    if (!mounted) return;
    setState(() {
      _clientNames
        ..clear()
        ..addEntries(clients.map((client) => MapEntry(client.id, client.name)));
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange(
    BuildContext context,
    StateSetter setModalState,
  ) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: (_startDate != null && _endDate != null)
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.emerald,
              onPrimary: AppTheme.bgDeep,
              surface: AppTheme.bgCard,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      setModalState(() {});
    }
  }

  void _openFilterModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final hasActiveFilters =
                _paymentMethodFilter != 'All' ||
                _sortBy != 'Newest' ||
                _startDate != null ||
                _endDate != null;
            return Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
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
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: AppTheme.glassBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Filter & Sort', style: AppTheme.headlineMedium()),
                      if (hasActiveFilters)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _paymentMethodFilter = 'All';
                              _sortBy = 'Newest';
                              _startDate = null;
                              _endDate = null;
                            });
                            setModalState(() {});
                          },
                          child: const Text(
                            'Reset All',
                            style: TextStyle(color: AppTheme.emerald),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Date Range Picker
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'DATE RANGE',
                        style: AppTheme.labelSmall(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      if (_startDate != null || _endDate != null)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _startDate = null;
                              _endDate = null;
                            });
                            setModalState(() {});
                          },
                          child: const Text(
                            'Clear Dates',
                            style: TextStyle(
                              color: AppTheme.errorRed,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _pickDateRange(context, setModalState),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (_startDate != null || _endDate != null)
                              ? AppTheme.emerald
                              : AppTheme.glassBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.date_range_rounded,
                                color: AppTheme.emerald,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                (_startDate != null && _endDate != null)
                                    ? '${formatDate(_startDate!)}  ➔  ${formatDate(_endDate!)}'
                                    : 'Choose Start & End Date',
                                style: TextStyle(
                                  color:
                                      (_startDate != null && _endDate != null)
                                      ? AppTheme.textPrimary
                                      : AppTheme.textHint,
                                  fontWeight:
                                      (_startDate != null && _endDate != null)
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppTheme.textHint,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'PAYMENT METHOD',
                    style: AppTheme.labelSmall(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _paymentMethodOptions.map((pm) {
                      final selected = _paymentMethodFilter == pm;
                      return ChoiceChip(
                        selected: selected,
                        label: Text(pm),
                        labelStyle: TextStyle(
                          color: selected
                              ? AppTheme.bgDeep
                              : AppTheme.textPrimary,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 13,
                        ),
                        selectedColor: AppTheme.emerald,
                        backgroundColor: AppTheme.bgSurface,
                        side: BorderSide(
                          color: selected
                              ? AppTheme.emerald
                              : AppTheme.glassBorder,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        showCheckmark: false,
                        onSelected: (val) {
                          if (val) {
                            setState(() => _paymentMethodFilter = pm);
                            setModalState(() {});
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'SORT BY',
                    style: AppTheme.labelSmall(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _sortOptions.map((sort) {
                      final selected = _sortBy == sort;
                      return ChoiceChip(
                        selected: selected,
                        label: Text(sort),
                        labelStyle: TextStyle(
                          color: selected
                              ? AppTheme.bgDeep
                              : AppTheme.textPrimary,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 13,
                        ),
                        selectedColor: AppTheme.emerald,
                        backgroundColor: AppTheme.bgSurface,
                        side: BorderSide(
                          color: selected
                              ? AppTheme.emerald
                              : AppTheme.glassBorder,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        showCheckmark: false,
                        onSelected: (val) {
                          if (val) {
                            setState(() => _sortBy = sort);
                            setModalState(() {});
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emerald,
                        foregroundColor: AppTheme.bgDeep,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMD,
                          ),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Apply Filters',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoiceListProvider);
    final isFilterActive =
        _paymentMethodFilter != 'All' ||
        _sortBy != 'Newest' ||
        _startDate != null ||
        _endDate != null;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDeep,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          'All Invoices',
          style: AppTheme.headlineMedium().copyWith(fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),

            // Search Bar & Filter Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.glassBorder),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: AppTheme.bodyMedium(),
                        onChanged: (val) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search invoice, client, or details',
                          hintStyle: AppTheme.bodyMedium(
                            color: AppTheme.textHint,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: AppTheme.textHint,
                            size: 20,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  child: const Icon(
                                    Icons.clear_rounded,
                                    color: AppTheme.textHint,
                                    size: 18,
                                  ),
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Filter Glass Button with Active Indicator
                  GestureDetector(
                    onTap: () => _openFilterModal(context),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: 46,
                          width: 46,
                          decoration: BoxDecoration(
                            color: isFilterActive
                                ? AppTheme.emerald.withAlpha(30)
                                : AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isFilterActive
                                  ? AppTheme.emerald
                                  : AppTheme.glassBorder,
                            ),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            color: isFilterActive
                                ? AppTheme.emerald
                                : AppTheme.textPrimary,
                            size: 22,
                          ),
                        ),
                        if (isFilterActive)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: AppTheme.emerald,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.bgDeep,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Status Segmented Control
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Row(
                children: _statusOptions.map((status) {
                  final isSelected = _statusFilter == status;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _statusFilter = status),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.emerald
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              status,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSelected
                                    ? AppTheme.bgDeep
                                    : AppTheme.textSecondary,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 12),

            // Filtered Invoice List
            Expanded(
              child: invoicesAsync.when(
                data: (invoices) {
                  final search = _searchController.text.trim().toLowerCase();
                  var filtered = invoices.where((inv) {
                    // Status
                    if (_statusFilter != 'All') {
                      if (inv.status.displayName.toLowerCase() !=
                          _statusFilter.toLowerCase()) {
                        return false;
                      }
                    }
                    // Payment Method
                    if (_paymentMethodFilter != 'All') {
                      final pm = inv.paymentMethod ?? 'Bank Transfer';
                      if (pm.toLowerCase() !=
                          _paymentMethodFilter.toLowerCase()) {
                        return false;
                      }
                    }
                    // Date Range
                    if (_startDate != null) {
                      final startOfDay = DateTime(
                        _startDate!.year,
                        _startDate!.month,
                        _startDate!.day,
                      );
                      if (inv.date.isBefore(startOfDay)) return false;
                    }
                    if (_endDate != null) {
                      final endOfDay = DateTime(
                        _endDate!.year,
                        _endDate!.month,
                        _endDate!.day,
                        23,
                        59,
                        59,
                      );
                      if (inv.date.isAfter(endOfDay)) return false;
                    }
                    // Search Query
                    if (search.isNotEmpty) {
                      final numMatch = inv.invoiceNumber.toLowerCase().contains(
                        search,
                      );
                      final noteMatch =
                          inv.notes?.toLowerCase().contains(search) ?? false;
                      final clientMatch = (_clientNames[inv.clientId] ?? '')
                          .toLowerCase()
                          .contains(search);
                      if (!numMatch && !noteMatch && !clientMatch) return false;
                    }
                    return true;
                  }).toList();

                  // Sort
                  if (_sortBy == 'Oldest') {
                    filtered.sort((a, b) => a.date.compareTo(b.date));
                  } else if (_sortBy == 'Highest Amount') {
                    filtered.sort(
                      (a, b) => b.totalAmount.compareTo(a.totalAmount),
                    );
                  } else if (_sortBy == 'Client') {
                    filtered.sort(
                      (a, b) => (_clientNames[a.clientId] ?? '')
                          .toLowerCase()
                          .compareTo(
                            (_clientNames[b.clientId] ?? '').toLowerCase(),
                          ),
                    );
                  } else {
                    filtered.sort((a, b) => b.date.compareTo(a.date));
                  }

                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: GlassCard(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.receipt_long_outlined,
                                color: AppTheme.emerald,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                invoices.isEmpty
                                    ? 'Create your first invoice in seconds'
                                    : 'No invoices found',
                                style: AppTheme.titleLarge(),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                invoices.isEmpty
                                    ? 'Create a professional invoice, quote, or estimate from the + button.'
                                    : 'No invoices match your current search or filters.',
                                style: AppTheme.bodyMedium(),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final inv = filtered[index];
                      return Dismissible(
                        key: ValueKey('invoice-${inv.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.only(right: 20),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: AppTheme.errorRed.withAlpha(180),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMD,
                            ),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                          ),
                        ),
                        confirmDismiss: (_) => _confirmDelete(context, inv),
                        onDismissed: (_) async {
                          await ref
                              .read(invoiceActionsProvider)
                              .deleteInvoice(inv.id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InvoiceTile(
                            invoice: inv,
                            onTap: () =>
                                _showInvoiceActionSheet(context, ref, inv),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.emerald,
                    strokeWidth: 2.5,
                  ),
                ),
                error: (e, _) => Center(
                  child: Text(
                    'Failed to load invoices: $e',
                    style: AppTheme.bodyMedium(color: AppTheme.errorRed),
                  ),
                ),
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
    final currency = ref.read(currencySymbolProvider);
    final currencyCode = ref.read(currencyCodeProvider);
    final client = await db.getClientById(invoice.clientId);
    final clientName = client?.name ?? 'Client #${invoice.clientId}';

    if (!context.mounted) return;

    var selectedStatus = invoice.status;
    const editableStatuses = [
      InvoiceStatus.draft,
      InvoiceStatus.pending,
      InvoiceStatus.paid,
      InvoiceStatus.overdue,
      InvoiceStatus.cancelled,
    ];

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

                  // Status buttons — wrapped so labels never clip on smaller iPhones.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: editableStatuses.map((status) {
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

                      return SizedBox(
                        width: 92,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () async {
                              setModalState(() {
                                selectedStatus = status;
                              });

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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 48),
                            foregroundColor: AppTheme.textPrimary,
                            side: const BorderSide(color: AppTheme.glassBorder),
                          ),
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: const Text('Duplicate'),
                          onPressed: () async {
                            Navigator.of(modalContext).pop();
                            await _duplicateInvoice(context, ref, invoice);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(44, 48),
                            foregroundColor: AppTheme.errorRed,
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('Delete'),
                          onPressed: () async {
                            final confirmed = await _confirmDelete(
                              context,
                              invoice,
                            );
                            if (!confirmed || !modalContext.mounted) return;
                            Navigator.of(modalContext).pop();
                            await ref
                                .read(invoiceActionsProvider)
                                .deleteInvoice(invoice.id);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context, Invoice invoice) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          'Delete ${invoice.documentType == 'quote' ? 'quote' : 'invoice'}?',
          style: AppTheme.titleLarge(),
        ),
        content: Text(
          'This removes ${invoice.invoiceNumber} from this device.',
          style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.errorRed),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _duplicateInvoice(
    BuildContext context,
    WidgetRef ref,
    Invoice invoice,
  ) async {
    final db = ref.read(databaseServiceProvider);
    final items = await db.getItemsForInvoice(invoice.id);
    final prefix = invoice.documentType == 'quote' ? 'QUO' : 'INV';
    final nextNumber = await ref
        .read(invoiceActionsProvider)
        .generateInvoiceNumber(prefix: prefix);
    final entry = InvoicesCompanion.insert(
      invoiceNumber: nextNumber,
      date: DateTime.now(),
      clientId: invoice.clientId,
      totalAmount: Value(invoice.totalAmount),
      taxRate: Value(invoice.taxRate),
      status: const Value(InvoiceStatus.draft),
      language: Value(invoice.language),
      template: Value(invoice.template),
      documentType: Value(invoice.documentType),
      paymentMethod: Value(invoice.paymentMethod),
      notes: Value(invoice.notes),
    );
    final itemEntries = items
        .map(
          (item) => InvoiceItemsCompanion.insert(
            description: item.description,
            unitPrice: item.unitPrice,
            quantity: Value(item.quantity),
          ),
        )
        .toList();
    final result = await ref
        .read(invoiceActionsProvider)
        .addInvoiceGated(entry, itemEntries);
    if (!context.mounted) return;
    if (result is FreemiumLimitReached) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const PaywallScreen(reason: PaywallReason.freeLimit),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.emerald,
        content: Text(
          'Draft $nextNumber created.',
          style: AppTheme.bodyMedium(color: AppTheme.bgDeep),
        ),
      ),
    );
  }
}
