import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/invoice.dart';
import '../providers/client_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/database_provider.dart';
import '../providers/invoice_provider.dart';
import '../providers/tax_rate_provider.dart';
import '../services/analytics_service.dart';
import '../screens/paywall_screen.dart';
import '../services/app_database.dart';
import '../services/revenuecat_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/glass_card.dart';

/// Helper model for temporary form state of a single invoice line item.
class _ItemFormRow {
  _ItemFormRow()
    : descController = TextEditingController(),
      priceController = TextEditingController(),
      qtyController = TextEditingController();

  final TextEditingController descController;
  final TextEditingController priceController;
  final TextEditingController qtyController;

  double get unitPrice => double.tryParse(priceController.text.trim()) ?? 0.0;
  int get quantity => int.tryParse(qtyController.text.trim()) ?? 1;
  double get lineTotal => unitPrice * quantity;

  void dispose() {
    descController.dispose();
    priceController.dispose();
    qtyController.dispose();
  }
}

/// Screen for creating a new invoice or editing an existing invoice/quote.
class CreateInvoiceScreen extends ConsumerStatefulWidget {
  const CreateInvoiceScreen({
    super.key,
    this.existingInvoice,
    this.isQuote = false,
    this.initialClientName,
    this.initialItems,
    this.initialNotes,
  });

  final Invoice? existingInvoice;
  final bool isQuote;
  final String? initialClientName;
  final List<Map<String, dynamic>>? initialItems;
  final String? initialNotes;

  @override
  ConsumerState<CreateInvoiceScreen> createState() =>
      _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends ConsumerState<CreateInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();

  late bool _isQuote;
  late String _invoiceNumber;
  DateTime _selectedDate = DateTime.now();
  InvoiceStatus _selectedStatus = InvoiceStatus.pending;
  String _selectedLanguage = 'English';
  String _selectedTemplate = 'Basic';
  String? _previewedTemplate;
  String _selectedPaymentMethod = 'Bank transfer';
  final _paymentMethods = const [
    'Bank transfer',
    'IBAN',
    'Routing number',
    'PayPal',
    'Stripe',
    'Cash',
    'Other',
  ];
  final _customPaymentMethodController = TextEditingController();
  final _notesController = TextEditingController();
  final _taxRateController = TextEditingController();

  Client? _selectedClient;
  final List<_ItemFormRow> _items = [];
  bool _isSaving = false;

  bool get isEditing => widget.existingInvoice != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final inv = widget.existingInvoice!;
      _isQuote = inv.documentType == 'quote';
      _invoiceNumber = inv.invoiceNumber;
      _selectedDate = inv.date;
      _selectedStatus = inv.status;
      _selectedLanguage = inv.language ?? 'English';
      _selectedTemplate = inv.template ?? 'Basic';
      final rawPm = inv.paymentMethod ?? 'Bank transfer';
      final normalizedPm = rawPm == 'Bank Transfer' ? 'Bank transfer' : rawPm;
      if (_paymentMethods.contains(normalizedPm) && normalizedPm != 'Other') {
        _selectedPaymentMethod = normalizedPm;
      } else {
        _selectedPaymentMethod = 'Other';
        _customPaymentMethodController.text = rawPm == 'Other' ? '' : rawPm;
      }
      _taxRateController.text = inv.taxRate == 0 ? '' : inv.taxRate.toString();
      _notesController.text = inv.notes ?? '';
      _loadExistingData(inv);
    } else {
      _isQuote = widget.isQuote;
      _invoiceNumber =
          'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

      final defaultTaxRate = ref.read(defaultTaxRateProvider);
      _taxRateController.text = defaultTaxRate == 0
          ? ''
          : defaultTaxRate.toStringAsFixed(
              defaultTaxRate.truncateToDouble() == defaultTaxRate ? 0 : 1,
            );
      _notesController.text = widget.initialNotes ?? '';

      // Handle AI initial items
      if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
        for (final item in widget.initialItems!) {
          final row = _ItemFormRow();
          row.descController.text = item['description']?.toString() ?? '';
          row.priceController.text = item['unitPrice']?.toString() ?? '0.0';
          row.qtyController.text = item['quantity']?.toString() ?? '1';
          _items.add(row);
        }
      } else {
        _addItemRow();
      }
      _initInvoiceNumber();
      _matchInitialClient();
    }
  }

  Future<void> _matchInitialClient() async {
    if (widget.initialClientName == null || widget.initialClientName!.isEmpty) {
      return;
    }

    final db = ref.read(databaseServiceProvider);
    final allClients = await db.getAllClients();
    final nameLower = widget.initialClientName!.toLowerCase();

    for (final c in allClients) {
      if (c.name.toLowerCase().contains(nameLower) ||
          nameLower.contains(c.name.toLowerCase())) {
        if (mounted) {
          setState(() {
            _selectedClient = c;
          });
        }
        break;
      }
    }
  }

  Future<void> _loadExistingData(Invoice inv) async {
    final db = ref.read(databaseServiceProvider);
    final client = await db.getClientById(inv.clientId);
    final items = await db.getItemsForInvoice(inv.id);

    if (!mounted) return;
    setState(() {
      _selectedClient = client;
      _items.clear();
      if (items.isNotEmpty) {
        for (final item in items) {
          final row = _ItemFormRow();
          row.descController.text = item.description;
          row.priceController.text = item.unitPrice == 0
              ? ''
              : item.unitPrice.toStringAsFixed(2);
          row.qtyController.text = item.quantity == 1
              ? ''
              : item.quantity.toString();
          _items.add(row);
        }
      } else {
        _addItemRow();
      }
    });
  }

  Future<void> _initInvoiceNumber() async {
    final prefix = _isQuote ? 'QUO' : 'INV';
    final nextNumber = await ref
        .read(invoiceActionsProvider)
        .generateInvoiceNumber(prefix: prefix);
    if (mounted) {
      setState(() {
        _invoiceNumber = nextNumber;
      });
    }
  }

  @override
  void dispose() {
    _taxRateController.dispose();
    _customPaymentMethodController.dispose();
    _notesController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItemRow() {
    setState(() {
      _items.add(_ItemFormRow());
    });
  }

  void _removeItemRow(int index) {
    if (_items.length <= 1) return;
    setState(() {
      final removed = _items.removeAt(index);
      removed.dispose();
    });
  }

  double get _subtotal => _items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get _taxRate => double.tryParse(_taxRateController.text.trim()) ?? 0.0;
  double get _taxAmount => _subtotal * (_taxRate / 100);
  double get _grandTotal => _subtotal + _taxAmount;

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      builder: (context, child) {
        return Theme(
          data: AppTheme.darkTheme.copyWith(
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
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _openAddClientModal() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final taxIdController = TextEditingController();
    final phoneController = TextEditingController();
    final countryController = TextEditingController();
    String selectedLanguage = 'English';
    String selectedTaxLabel = 'Tax ID';
    final taxLabels = [
      'Tax ID',
      'EIN',
      'VAT ID',
      'VAT',
      'ICE',
      'SIRET',
      'NIF',
      'ABN',
      'GST',
      'TIN',
      'SSN',
      'Other',
    ];
    final modalFormKey = GlobalKey<FormState>();

    final createdClient = await showModalBottomSheet<Client>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                decoration: const BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppTheme.radiusXL),
                  ),
                  border: Border(
                    top: BorderSide(color: AppTheme.glassBorder, width: 1.5),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                child: Form(
                  key: modalFormKey,
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.electricBlue.withAlpha(25),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: AppTheme.electricBlue.withAlpha(90),
                                ),
                              ),
                              child: const Icon(
                                Icons.person_add_alt_1_rounded,
                                color: AppTheme.electricBlue,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Add new client',
                                    style: AppTheme.headlineMedium(),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Save client details for faster invoicing.',
                                    style: AppTheme.bodyMedium(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              constraints: const BoxConstraints(
                                minWidth: 44,
                                minHeight: 44,
                              ),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'CLIENT INFORMATION',
                          style: AppTheme.labelSmall(
                            color: AppTheme.electricBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: nameController,
                          label: 'Client Name *',
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Name is required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: addressController,
                          label: 'Address (Optional)',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'TAX DETAILS',
                          style: AppTheme.labelSmall(
                            color: AppTheme.electricBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tax ID type (Optional)',
                                    style: AppTheme.labelSmall(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.bgSurface,
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.radiusSM,
                                      ),
                                      border: Border.all(
                                        color: AppTheme.glassBorder,
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: selectedTaxLabel,
                                        dropdownColor: AppTheme.bgCard,
                                        isExpanded: true,
                                        style: AppTheme.bodyMedium(),
                                        items: taxLabels.map((lbl) {
                                          return DropdownMenuItem(
                                            value: lbl,
                                            child: Text(lbl),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setModalState(
                                              () => selectedTaxLabel = val,
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: _buildTextField(
                                controller: taxIdController,
                                label: 'Tax Number (Optional)',
                                hint: 'Enter tax number...',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'CONTACT & LOCALIZATION',
                          style: AppTheme.labelSmall(
                            color: AppTheme.electricBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: countryController,
                                label: 'Country (Optional)',
                                hint: 'e.g. France, USA, Morocco',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTextField(
                                controller: phoneController,
                                label: 'Phone (Optional)',
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Invoice language',
                              style: AppTheme.labelSmall(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.bgSurface,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSM,
                                ),
                                border: Border.all(color: AppTheme.glassBorder),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedLanguage,
                                  dropdownColor: AppTheme.bgCard,
                                  isExpanded: true,
                                  style: AppTheme.bodyMedium(),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'English',
                                      child: Text('English'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'French',
                                      child: Text('French'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Arabic',
                                      child: Text('Arabic'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Spanish',
                                      child: Text('Spanish'),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setModalState(
                                        () => selectedLanguage = val,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.emerald,
                              foregroundColor: AppTheme.bgDeep,
                              elevation: 8,
                              shadowColor: AppTheme.emeraldGlow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMD,
                                ),
                              ),
                            ),
                            onPressed: () async {
                              if (modalFormKey.currentState!.validate()) {
                                final taxIdVal = taxIdController.text.trim();
                                final formattedTaxId = taxIdVal.isEmpty
                                    ? null
                                    : '$selectedTaxLabel: $taxIdVal';

                                final id = await ref
                                    .read(clientActionsProvider)
                                    .addClient(
                                      name: nameController.text.trim(),
                                      address:
                                          addressController.text.trim().isEmpty
                                          ? null
                                          : addressController.text.trim(),
                                      taxId: formattedTaxId,
                                      phone: phoneController.text.trim().isEmpty
                                          ? null
                                          : phoneController.text.trim(),
                                      country:
                                          countryController.text.trim().isEmpty
                                          ? null
                                          : countryController.text.trim(),
                                      language: selectedLanguage,
                                    );
                                if (context.mounted) {
                                  final newClient = Client(
                                    id: id,
                                    name: nameController.text.trim(),
                                    address:
                                        addressController.text.trim().isEmpty
                                        ? null
                                        : addressController.text.trim(),
                                    taxId: formattedTaxId,
                                    phone: phoneController.text.trim().isEmpty
                                        ? null
                                        : phoneController.text.trim(),
                                    country:
                                        countryController.text.trim().isEmpty
                                        ? null
                                        : countryController.text.trim(),
                                    language: selectedLanguage,
                                  );
                                  Navigator.of(context).pop(newClient);
                                }
                              }
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_rounded, size: 21),
                                const SizedBox(width: 8),
                                Text(
                                  'Save client',
                                  style: AppTheme.bodyLarge(
                                    color: AppTheme.bgDeep,
                                  ).copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    addressController.dispose();
    taxIdController.dispose();
    phoneController.dispose();
    countryController.dispose();

    if (createdClient != null) {
      setState(() => _selectedClient = createdClient);
    }
  }

  Future<void> _saveInvoice() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or create a client first.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    // Validate items
    bool hasValidItem = false;
    for (final item in _items) {
      if (item.descController.text.trim().isNotEmpty && item.unitPrice > 0) {
        hasValidItem = true;
        break;
      }
    }

    if (!hasValidItem) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add at least one line item with a description and price.',
          ),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final itemEntries = _items
          .where((i) => i.descController.text.trim().isNotEmpty)
          .map(
            (i) => InvoiceItemsCompanion.insert(
              description: i.descController.text.trim(),
              unitPrice: i.unitPrice,
              quantity: Value(i.quantity),
            ),
          )
          .toList();

      final effectivePaymentMethod = _selectedPaymentMethod == 'Other'
          ? (_customPaymentMethodController.text.trim().isEmpty
                ? 'Other'
                : _customPaymentMethodController.text.trim())
          : _selectedPaymentMethod;

      if (isEditing) {
        final invoiceEntry = InvoicesCompanion(
          id: Value(widget.existingInvoice!.id),
          invoiceNumber: Value(_invoiceNumber),
          date: Value(_selectedDate),
          clientId: Value(_selectedClient!.id),
          totalAmount: Value(_grandTotal),
          taxRate: Value(_taxRate),
          status: Value(_selectedStatus),
          language: Value(_selectedLanguage),
          template: Value(_selectedTemplate),
          documentType: Value(_isQuote ? 'quote' : 'invoice'),
          paymentMethod: Value(effectivePaymentMethod),
          notes: Value(
            _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          ),
        );

        await ref.read(invoiceActionsProvider).updateInvoice(invoiceEntry);
        await ref
            .read(invoiceActionsProvider)
            .replaceItems(widget.existingInvoice!.id, itemEntries);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.emerald,
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppTheme.bgDeep),
                const SizedBox(width: 10),
                Text(
                  '${_isQuote ? "Quote" : "Invoice"} $_invoiceNumber updated!',
                  style: AppTheme.bodyMedium(color: AppTheme.bgDeep),
                ),
              ],
            ),
          ),
        );
        Navigator.of(context).pop();
      } else {
        final invoiceEntry = InvoicesCompanion.insert(
          invoiceNumber: _invoiceNumber,
          date: _selectedDate,
          clientId: _selectedClient!.id,
          totalAmount: Value(_grandTotal),
          taxRate: Value(_taxRate),
          status: Value(_selectedStatus),
          language: Value(_selectedLanguage),
          template: Value(_selectedTemplate),
          documentType: Value(_isQuote ? 'quote' : 'invoice'),
          paymentMethod: Value(effectivePaymentMethod),
          notes: Value(
            _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          ),
        );

        final result = await ref
            .read(invoiceActionsProvider)
            .addInvoiceGated(invoiceEntry, itemEntries);

        if (!mounted) return;

        switch (result) {
          case InvoiceCreated():
            unawaited(
              AnalyticsService.track(
                _isQuote ? 'quote_created' : 'invoice_created',
              ),
            );
            if (!_isQuote) {
              unawaited(AnalyticsService.trackOnce('first_invoice_created'));
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.emerald,
                content: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: AppTheme.bgDeep,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Invoice $_invoiceNumber saved!',
                      style: AppTheme.bodyMedium(color: AppTheme.bgDeep),
                    ),
                  ],
                ),
              ),
            );
            Navigator.of(context).pop();

          case FreemiumLimitReached():
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const PaywallScreen(reason: PaywallReason.freeLimit),
              ),
            );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving invoice: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientListProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          isEditing
              ? (_isQuote ? 'Edit Quote' : 'Edit Invoice')
              : (_isQuote ? 'Create Quote' : 'Create Invoice'),
          style: AppTheme.titleLarge(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.glassBorder),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // ── Header / Invoice Meta Card ─────────────────────────────────
              _buildMetaCard(),
              const SizedBox(height: 24),

              // ── Client Selection Section ───────────────────────────────────
              _buildClientSection(clientsAsync),
              const SizedBox(height: 24),

              // ── Line Items Section ─────────────────────────────────────────
              _buildItemsSection(),
              const SizedBox(height: 24),

              // ── Summary Card ───────────────────────────────────────────────
              _buildSummaryCard(),
              const SizedBox(height: 24),

              // ── Invoice Template Selector ─────────────────────────────────
              _buildTemplateSection(),
              const SizedBox(height: 32),

              // ── Save Button ────────────────────────────────────────────────
              SizedBox(
                height: 58,
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
                  onPressed: _isSaving ? null : _saveInvoice,
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AppTheme.bgDeep,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_rounded, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              isEditing
                                  ? (_isQuote ? 'Update Quote' : 'Save Invoice')
                                  : (_isQuote ? 'Save Quote' : 'Save Invoice'),
                              style: AppTheme.titleLarge(
                                color: AppTheme.bgDeep,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section Builders ────────────────────────────────────────────────────────

  Widget _buildMetaCard() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isQuote ? 'QUOTE NUMBER' : 'INVOICE NUMBER',
                      style: AppTheme.labelSmall(),
                    ),
                    const SizedBox(height: 4),
                    Text(_invoiceNumber, style: AppTheme.titleLarge()),
                  ],
                ),
              ),
              // Date picker button
              GestureDetector(
                onTap: _selectDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: AppTheme.emerald,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                        style: AppTheme.bodyMedium(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Status & Tax Rate row
          if (_isQuote) ...[
            // For quotes: only show tax rate full width
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tax rate (Optional)', style: AppTheme.labelSmall()),
                const SizedBox(height: 6),
                _buildTextField(
                  controller: _taxRateController,
                  label: 'Default tax rate for this document',
                  hint: 'Leave blank for no tax',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ] else ...[
            // For Invoices: show Status & Tax Rate in a Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('STATUS', style: AppTheme.labelSmall()),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurface,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSM,
                          ),
                          border: Border.all(color: AppTheme.glassBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<InvoiceStatus>(
                            value: _selectedStatus,
                            dropdownColor: AppTheme.bgCard,
                            isExpanded: true,
                            style: AppTheme.bodyMedium(),
                            items: InvoiceStatus.values.map((status) {
                              final label = status.displayName;
                              return DropdownMenuItem(
                                value: status,
                                child: Text(label),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedStatus = val);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tax rate (Optional)', style: AppTheme.labelSmall()),
                      const SizedBox(height: 6),
                      _buildTextField(
                        controller: _taxRateController,
                        label: 'Default tax rate for this document',
                        hint: 'Leave blank for no tax',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),

          // Language selector
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isQuote ? 'QUOTE LANGUAGE' : 'INVOICE LANGUAGE',
                style: AppTheme.labelSmall(),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedLanguage,
                    dropdownColor: AppTheme.bgCard,
                    isExpanded: true,
                    style: AppTheme.bodyMedium(),
                    items: const [
                      DropdownMenuItem(
                        value: 'English',
                        child: Text('English'),
                      ),
                      DropdownMenuItem(
                        value: 'Français',
                        child: Text('Français'),
                      ),
                      DropdownMenuItem(
                        value: 'Español',
                        child: Text('Español'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedLanguage = val);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),

          // Payment details (only for invoices)
          if (!_isQuote) ...[
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment details', style: AppTheme.labelSmall()),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _paymentMethods.contains(_selectedPaymentMethod)
                          ? _selectedPaymentMethod
                          : _paymentMethods.first,
                      dropdownColor: AppTheme.bgCard,
                      isExpanded: true,
                      style: AppTheme.bodyMedium(),
                      items: _paymentMethods.map((pm) {
                        return DropdownMenuItem(value: pm, child: Text(pm));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedPaymentMethod = val);
                        }
                      },
                    ),
                  ),
                ),
                if (_selectedPaymentMethod == 'Other') ...[
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _customPaymentMethodController,
                    label: 'Custom payment method (Optional)',
                    hint: 'Describe how your client can pay',
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 14),
          // Custom Footer Note / Thank You Message
          _buildTextField(
            controller: _notesController,
            label: 'Notes (Optional)',
            hint: 'e.g. Thank you for your business!',
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildClientSection(AsyncValue<List<Client>> clientsAsync) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CLIENT DETAILS', style: AppTheme.labelSmall()),
              const Spacer(),
              TextButton.icon(
                onPressed: _openAddClientModal,
                icon: const Icon(Icons.add, size: 16, color: AppTheme.emerald),
                label: Text(
                  'Add New',
                  style: AppTheme.bodyMedium(color: AppTheme.emerald),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          clientsAsync.when(
            data: (clients) {
              if (clients.isEmpty && _selectedClient == null) {
                return GestureDetector(
                  onTap: _openAddClientModal,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      border: Border.all(
                        color: AppTheme.emerald.withAlpha(80),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.person_add_outlined,
                          color: AppTheme.emerald,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'No clients saved. Tap to add one.',
                          style: AppTheme.bodyMedium(color: AppTheme.emerald),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Client>(
                    value: clients.any((c) => c.id == _selectedClient?.id)
                        ? clients.firstWhere((c) => c.id == _selectedClient?.id)
                        : _selectedClient,
                    hint: Text(
                      'Select Client',
                      style: AppTheme.bodyMedium(color: AppTheme.textHint),
                    ),
                    dropdownColor: AppTheme.bgCard,
                    isExpanded: true,
                    style: AppTheme.bodyMedium(),
                    items: clients.map((c) {
                      return DropdownMenuItem<Client>(
                        value: c,
                        child: Text(c.name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() => _selectedClient = val);
                    },
                  ),
                ),
              );
            },
            loading: () => const SizedBox(
              height: 48,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.emerald,
                  strokeWidth: 2,
                ),
              ),
            ),
            error: (e, _) => Text(
              'Error loading clients: $e',
              style: AppTheme.bodyMedium(color: AppTheme.errorRed),
            ),
          ),

          // Display selected client details summary if chosen
          if (_selectedClient != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgDeep,
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_selectedClient!.name, style: AppTheme.bodyLarge()),
                  if (_selectedClient!.address != null)
                    Text(
                      _selectedClient!.address!,
                      style: AppTheme.bodyMedium(),
                    ),
                  if (_selectedClient!.taxId != null)
                    Text(
                      'Tax ID: ${_selectedClient!.taxId!}',
                      style: AppTheme.labelSmall(),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsSection() {
    final currency = ref.watch(currencySymbolProvider);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('INVOICE ITEMS', style: AppTheme.labelSmall()),
              const Spacer(),
              TextButton.icon(
                onPressed: _addItemRow,
                icon: const Icon(Icons.add, size: 16, color: AppTheme.emerald),
                label: Text(
                  'Add Item',
                  style: AppTheme.bodyMedium(color: AppTheme.emerald),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._items.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Item #${idx + 1}',
                        style: AppTheme.labelSmall(color: AppTheme.emerald),
                      ),
                      const Spacer(),
                      if (_items.length > 1)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppTheme.errorRed,
                            size: 18,
                          ),
                          onPressed: () => _removeItemRow(idx),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: item.descController,
                    label: 'Description',
                    hint: 'e.g. Web Development Services',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          controller: item.priceController,
                          label: 'Price ($currency)',
                          hint: '0.00',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: _buildTextField(
                          controller: item.qtyController,
                          label: 'Qty',
                          hint: '1',
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('TOTAL', style: AppTheme.labelSmall()),
                            const SizedBox(height: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                _fmtAmt(currency, item.lineTotal),
                                style: AppTheme.bodyLarge(
                                  color: AppTheme.emerald,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _fmtAmt(String currency, double amount) {
    return formatCurrency(
      amount,
      currency,
      currencyCode: ref.read(currencyCodeProvider),
    );
  }

  Widget _buildSummaryCard() {
    final currency = ref.watch(currencySymbolProvider);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _summaryRow('Subtotal', _fmtAmt(currency, _subtotal)),
          const SizedBox(height: 8),
          _summaryRow(
            'Tax (${_taxRate.toStringAsFixed(1)}%)',
            _fmtAmt(currency, _taxAmount),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: AppTheme.glassBorder),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('GRAND TOTAL', style: AppTheme.titleLarge()),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    _fmtAmt(currency, _grandTotal),
                    style: AppTheme.displayLarge(
                      color: AppTheme.emerald,
                    ).copyWith(fontSize: 26),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTheme.bodyMedium()),
        const SizedBox(width: 12),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(value, style: AppTheme.bodyLarge()),
          ),
        ),
      ],
    );
  }

  Future<void> _selectTemplate(String templateName) async {
    if (templateName == 'Basic') {
      setState(() => _selectedTemplate = 'Basic');
      return;
    }

    final isPro = await RevenueCatService.isProUser();
    if (!isPro) {
      if (mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
      }
      return;
    }

    setState(() => _selectedTemplate = templateName);
  }

  Widget _buildTemplateSection() {
    final templates = [
      {'name': 'Basic', 'isPro': false, 'desc': 'Clean Standard'},
      {'name': 'Modern', 'isPro': true, 'desc': 'Clean and professional'},
      {'name': 'Elite', 'isPro': true, 'desc': 'Branded and executive'},
    ];

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('INVOICE TEMPLATE', style: AppTheme.labelSmall()),
              const Spacer(),
              Text(
                'Active: $_selectedTemplate',
                style: AppTheme.bodyMedium(color: AppTheme.emerald),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.touch_app_rounded,
                size: 12,
                color: AppTheme.textHint,
              ),
              const SizedBox(width: 4),
              Text(
                'Tap a template to preview. Tap again to select.',
                style: AppTheme.labelSmall(color: AppTheme.textHint),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── Horizontally scrollable list ──────────────────────────────────
          SizedBox(
            height: 195,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final t = templates[index];
                final name = t['name'] as String;
                final isPro = t['isPro'] as bool;
                final desc = t['desc'] as String;
                final isSelected = _selectedTemplate == name;

                return GestureDetector(
                  onTap: () {
                    if (_previewedTemplate == name) {
                      _selectTemplate(name);
                    } else {
                      setState(() => _previewedTemplate = name);
                      _showTemplateLargePreview(context, name, isPro, desc);
                    }
                  },
                  onLongPress: () =>
                      _showTemplateLargePreview(context, name, isPro, desc),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 110,
                    margin: EdgeInsets.only(
                      right: 10,
                      left: index == 0 ? 0 : 0,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.emerald.withAlpha(25)
                          : AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.emerald
                            : AppTheme.glassBorder,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppTheme.emerald.withAlpha(40),
                                blurRadius: 12,
                                spreadRadius: 0,
                              ),
                            ]
                          : [],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Mini visual preview
                        _buildMiniTemplatePreview(name),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: AppTheme.bodyLarge(
                                  color: isSelected
                                      ? AppTheme.emerald
                                      : AppTheme.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isPro) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 13,
                                color: AppTheme.warningAmber,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          desc,
                          textAlign: TextAlign.center,
                          style: AppTheme.labelSmall(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (isPro) ...[
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.warningAmber.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PRO',
                              style: AppTheme.labelSmall(
                                color: AppTheme.warningAmber,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Shows a large preview with an explicit action to use the template.
  void _showTemplateLargePreview(
    BuildContext context,
    String name,
    bool isPro,
    String desc,
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 60,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: AppTheme.headlineMedium(
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (isPro) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.warningAmber.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppTheme.warningAmber.withAlpha(80),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome_rounded,
                              size: 12,
                              color: AppTheme.warningAmber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              name == 'Modern' ? 'PREMIUM' : 'PRO',
                              style: AppTheme.labelSmall(
                                color: AppTheme.warningAmber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Large preview
              Container(
                width: double.infinity,
                height: 360,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(80),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _getLargeLayout(name),
              ),
              const SizedBox(height: 16),
              // Description
              Text(
                desc,
                style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: const BorderSide(color: AppTheme.glassBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMD,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Dismiss'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emerald,
                        foregroundColor: AppTheme.bgDeep,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMD,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _selectTemplate(name);
                      },
                      child: const Text('Use this template'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds a large realistic invoice preview using 'x' as placeholder text.
  Widget _getLargeLayout(String type) {
    const xLight = Color(0xFFBBBBBB);
    const xDark = Color(0xFF333333);
    const xMid = Color(0xFF777777);
    const bg = Colors.white;

    // ── Shared invoice body ────────────────────────────────────────────────
    Widget body = Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Business name + invoice label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xxxxxxxxx Xxxxx',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: xDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'xxxxxxxx@xxx.xx',
                    style: TextStyle(fontSize: 7, color: xMid),
                  ),
                  Text(
                    '+xx xxx xxx xxxx',
                    style: TextStyle(fontSize: 7, color: xMid),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'INVOICE',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: xDark,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('#INV-XXXX', style: TextStyle(fontSize: 8, color: xMid)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          Divider(color: xLight, height: 1),
          const SizedBox(height: 10),

          // Bill To
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BILL TO',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: xMid,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Xxxxxxx Xxxxx',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: xDark,
                    ),
                  ),
                  Text(
                    'xxx xxxxxxx, xxxxx',
                    style: TextStyle(fontSize: 7, color: xMid),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'DATE',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: xMid,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'xx/xx/xxxx',
                    style: TextStyle(fontSize: 8, color: xDark),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'DUE DATE',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: xMid,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'xx/xx/xxxx',
                    style: TextStyle(fontSize: 8, color: xDark),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: xDark,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    'DESCRIPTION',
                    style: TextStyle(
                      color: bg,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'QTY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: bg,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'TOTAL',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: bg,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Table rows
          for (final _ in List.generate(3, (i) => i)) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F9F9),
                border: Border(bottom: BorderSide(color: xLight, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Xxxxxxxxx xxxxxx',
                      style: TextStyle(fontSize: 7, color: xDark),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      'x',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 7, color: xMid),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '\$xxx.xx',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 7, color: xDark),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          // Totals
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Subtotal: ',
                      style: TextStyle(fontSize: 8, color: xMid),
                    ),
                    Text(
                      '\$xxx.xx',
                      style: TextStyle(
                        fontSize: 8,
                        color: xDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tax (xx%): ',
                      style: TextStyle(fontSize: 8, color: xMid),
                    ),
                    Text('\$xx.xx', style: TextStyle(fontSize: 8, color: xMid)),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: xDark,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'TOTAL: ',
                        style: TextStyle(
                          color: bg,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '\$xxx.xx',
                        style: TextStyle(
                          color: bg,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // ── Template-specific chrome ───────────────────────────────────────────
    switch (type) {
      case 'Modern':
        return Column(
          children: [
            // Teal full-width header banner with business name
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              color: Colors.teal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xxxxxxxxx Xxxxx',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'xxxxxxxx@xxx.xx  ·  +xx xxx xxx xxxx',
                    style: TextStyle(
                      color: Colors.white.withAlpha(180),
                      fontSize: 8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'INVOICE #INV-XXXX',
                      style: TextStyle(
                        color: Colors.white.withAlpha(220),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Body without the business name header (already in banner)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BILL TO',
                              style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.bold,
                                color: xMid,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Xxxxxxx Xxxxx',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: xDark,
                              ),
                            ),
                            Text(
                              'xxx xxxxxxx, xxxxx',
                              style: TextStyle(fontSize: 7, color: xMid),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'DATE',
                              style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.bold,
                                color: xMid,
                              ),
                            ),
                            Text(
                              'xx/xx/xxxx',
                              style: TextStyle(fontSize: 8, color: xDark),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              'DESCRIPTION',
                              style: TextStyle(
                                color: bg,
                                fontSize: 7,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              'QTY',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: bg,
                                fontSize: 7,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'TOTAL',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: bg,
                                fontSize: 7,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final _ in List.generate(3, (i) => i))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: xLight, width: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                'Xxxxxxxxx xxxxxx',
                                style: TextStyle(fontSize: 7, color: xDark),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'x',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 7, color: xMid),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '\$xxx.xx',
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 7, color: xDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        color: Colors.teal,
                        child: Text(
                          'TOTAL: \$xxx.xx',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );

      case 'Elite':
        return Row(
          children: [
            // Dark sidebar
            Container(
              width: 65,
              color: const Color(0xFF1E293B),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Text(
                    'Xxx\nXxxx',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'xxxxxxxx\n@xxx.xx',
                    style: TextStyle(
                      color: Colors.white.withAlpha(120),
                      fontSize: 6.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(color: Colors.white.withAlpha(40), height: 1),
                  const SizedBox(height: 10),
                  Text(
                    'INVOICE',
                    style: TextStyle(
                      color: Colors.white.withAlpha(150),
                      fontSize: 6,
                      letterSpacing: 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '#INV-XXXX',
                    style: const TextStyle(color: Colors.white, fontSize: 7),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'DATE',
                    style: TextStyle(
                      color: Colors.white.withAlpha(150),
                      fontSize: 6,
                      letterSpacing: 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'xx/xx/xxxx',
                    style: const TextStyle(color: Colors.white, fontSize: 7),
                  ),
                ],
              ),
            ),
            // Main content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BILL TO',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: xMid,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Xxxxxxx Xxxxx',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: xDark,
                      ),
                    ),
                    Text(
                      'xxx xxxxxxx, xxxxx',
                      style: TextStyle(fontSize: 7, color: xMid),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      color: const Color(0xFF1E293B),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              'DESCRIPTION',
                              style: TextStyle(
                                color: bg,
                                fontSize: 6.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              'QTY',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: bg,
                                fontSize: 6.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'TOTAL',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: bg,
                                fontSize: 6.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final _ in List.generate(3, (i) => i))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: xLight, width: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                'Xxxxxxxxx xxxxxx',
                                style: TextStyle(fontSize: 7, color: xDark),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'x',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 7, color: xMid),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '\$xxx.xx',
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 7, color: xDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        color: const Color(0xFF1E293B),
                        child: Text(
                          'TOTAL: \$xxx.xx',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );

      case 'Basic':
      default:
        return body;
    }
  }

  // ── Miniature invoice preview widgets ─────────────────────────────────────

  Widget _buildMiniTemplatePreview(String type) {
    return Container(
      height: 60,
      width: 45,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _getMiniLayout(type),
    );
  }

  Widget _getMiniLayout(String type) {
    final lines = Padding(
      padding: const EdgeInsets.all(4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 2, width: 15, color: Colors.grey[400]),
          const SizedBox(height: 4),
          Container(height: 2, width: 25, color: Colors.grey[300]),
          const SizedBox(height: 2),
          Container(height: 2, width: 20, color: Colors.grey[300]),
          const Spacer(),
          Container(
            height: 4,
            width: double.infinity,
            color: Colors.grey[800],
          ), // table header
          const SizedBox(height: 2),
          Container(height: 2, width: double.infinity, color: Colors.grey[300]),
          const SizedBox(height: 2),
          Container(height: 2, width: double.infinity, color: Colors.grey[300]),
        ],
      ),
    );

    switch (type) {
      case 'Modern':
        return Column(
          children: [
            Container(height: 12, color: Colors.teal), // Dark header banner
            Expanded(child: lines),
          ],
        );
      case 'Elite':
        return Row(
          children: [
            Container(
              width: 10,
              color: const Color(0xFF1E293B),
            ), // Dark sidebar stripe
            Expanded(child: lines),
          ],
        );
      case 'Basic':
      default:
        return lines; // Plain white, clean layout
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      style: AppTheme.bodyMedium(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTheme.labelSmall(),
        hintText: hint,
        hintStyle: AppTheme.bodyMedium(color: AppTheme.textHint),
        filled: true,
        fillColor: AppTheme.bgSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSM),
          borderSide: const BorderSide(color: AppTheme.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSM),
          borderSide: const BorderSide(color: AppTheme.emerald),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSM),
          borderSide: const BorderSide(color: AppTheme.errorRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSM),
          borderSide: const BorderSide(color: AppTheme.errorRed),
        ),
      ),
    );
  }
}
