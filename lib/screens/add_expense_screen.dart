import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/expense.dart';
import '../services/app_database.dart';
import '../providers/currency_provider.dart';
import '../providers/entitlement_provider.dart';
import '../providers/expense_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'paywall_screen.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({
    super.key,
    this.existingExpense,
    this.initialAmount,
    this.initialCategory,
    this.initialNote,
    this.initialImagePath,
  });

  final Expense? existingExpense;
  final double? initialAmount;
  final String? initialCategory;
  final String? initialNote;
  final String? initialImagePath;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  ExpenseCategory _selectedCategory = ExpenseCategory.other;
  DateTime _selectedDate = DateTime.now();
  String? _receiptImagePath;
  bool _isLoading = false;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.existingExpense != null) {
      final exp = widget.existingExpense!;
      _amountController.text = exp.amount.toString();
      _noteController.text = exp.note;
      _selectedCategory = exp.category;
      _selectedDate = exp.date;
      _receiptImagePath = exp.receiptImagePath;
    } else {
      if (widget.initialAmount != null) {
        _amountController.text = widget.initialAmount.toString();
      }
      if (widget.initialNote != null) {
        _noteController.text = widget.initialNote!;
      }
      if (widget.initialCategory != null) {
        final match = ExpenseCategory.values.where(
          (c) => c.name.toLowerCase() == widget.initialCategory!.toLowerCase(),
        );
        if (match.isNotEmpty) {
          _selectedCategory = match.first;
        }
      }
      if (widget.initialImagePath != null) {
        _receiptImagePath = widget.initialImagePath;
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _attachReceipt() async {
    final proAsync = ref.read(entitlementProvider);
    final isPro = proAsync.value ?? false;

    if (!isPro) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text('Attach Receipt', style: AppTheme.titleLarge()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: AppTheme.emerald,
              ),
              title: Text('Take Photo', style: AppTheme.bodyMedium()),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppTheme.emerald,
              ),
              title: Text('Choose from Gallery', style: AppTheme.bodyMedium()),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70, // Compress to save space
        requestFullMetadata: false,
      );
      if (pickedFile != null) {
        setState(() => _receiptImagePath = pickedFile.path);
      }
    }
  }

  Future<void> _saveExpense() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter an amount')));
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid positive amount')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.existingExpense != null) {
        final updated = widget.existingExpense!.copyWith(
          amount: amount,
          category: _selectedCategory,
          date: _selectedDate,
          note: _noteController.text.trim(),
          receiptImagePath: Value(_receiptImagePath),
        );
        await ref.read(expenseActionsProvider).updateExpense(updated);
      } else {
        final result = await ref
            .read(expenseActionsProvider)
            .addExpenseGated(
              amount: amount,
              category: _selectedCategory,
              date: _selectedDate,
              note: _noteController.text.trim(),
              receiptImagePath: _receiptImagePath,
            );

        if (result is ExpenseFreemiumLimitReached) {
          if (mounted) {
            setState(() => _isLoading = false);
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const PaywallScreen(reason: PaywallReason.freeLimit),
              ),
            );
          }
          return;
        }

        unawaited(AnalyticsService.track('expense_created'));
        unawaited(AnalyticsService.trackOnce('first_expense_created'));
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save expense: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencySymbolProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.existingExpense != null ? 'Edit Expense' : 'Add Expense',
          style: AppTheme.headlineMedium(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.glassBorder),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.emerald),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Amount', style: AppTheme.labelSmall()),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: AppTheme.headlineMedium(),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          hintStyle: AppTheme.headlineMedium().copyWith(
                            color: AppTheme.textHint,
                          ),
                          prefixText: '$currency ',
                          prefixStyle: AppTheme.headlineMedium(),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const Divider(color: AppTheme.glassBorder, height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Category', style: AppTheme.labelSmall()),
                                const SizedBox(height: 8),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<ExpenseCategory>(
                                    value: _selectedCategory,
                                    dropdownColor: AppTheme.bgCard,
                                    icon: const Icon(
                                      Icons.arrow_drop_down,
                                      color: AppTheme.textSecondary,
                                    ),
                                    isExpanded: true,
                                    style: AppTheme.bodyLarge(),
                                    items: ExpenseCategory.values.map((cat) {
                                      return DropdownMenuItem(
                                        value: cat,
                                        child: Text(cat.label),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedCategory = val);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 50,
                            color: AppTheme.glassBorder,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: GestureDetector(
                              onTap: _pickDate,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Date', style: AppTheme.labelSmall()),
                                  const SizedBox(height: 16),
                                  Text(
                                    '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                    style: AppTheme.bodyLarge(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Note', style: AppTheme.labelSmall()),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _noteController,
                        style: AppTheme.bodyMedium(),
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'e.g. Flight to conference',
                          hintStyle: AppTheme.bodyMedium().copyWith(
                            color: AppTheme.textHint,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('RECEIPT', style: AppTheme.labelSmall()),
                const SizedBox(height: 12),
                if (_receiptImagePath != null)
                  GestureDetector(
                    onTap: () {
                      final file = File(_receiptImagePath!);
                      if (!file.existsSync()) return;
                      showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          insetPadding: EdgeInsets.zero,
                          backgroundColor: Colors.black,
                          child: Stack(
                            children: [
                              Center(
                                child: InteractiveViewer(
                                  minScale: 0.5,
                                  maxScale: 4.0,
                                  child: Image.file(file, fit: BoxFit.contain),
                                ),
                              ),
                              Positioned(
                                top: 50,
                                right: 20,
                                child: SafeArea(
                                  child: IconButton(
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                    ),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            File(_receiptImagePath!),
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _receiptImagePath = null),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  GestureDetector(
                    onTap: _attachReceipt,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withAlpha(15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.emerald.withAlpha(60),
                          style: BorderStyle.solid,
                          width:
                              2, // Ideally dashed, but solid is simpler without custom painter
                        ),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.camera_alt_rounded,
                            color: AppTheme.emerald,
                            size: 32,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Attach Receipt',
                            style: AppTheme.bodyLarge().copyWith(
                              color: AppTheme.emerald,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: AppTheme.emeraldGradient,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'PRO',
                              style: AppTheme.labelSmall(
                                color: AppTheme.bgDeep,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emerald,
                      foregroundColor: AppTheme.bgDeep,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      ),
                    ),
                    onPressed: _saveExpense,
                    child: Text(
                      'Save Expense',
                      style: AppTheme.titleLarge(color: AppTheme.bgDeep),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}
