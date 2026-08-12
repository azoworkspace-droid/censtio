import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_database.dart';
import '../providers/currency_provider.dart';
import '../providers/expense_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'add_expense_screen.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expenseListProvider);
    final currency = ref.watch(currencySymbolProvider);
    final currencyCode = ref.watch(currencyCodeProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDeep,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          'Expenses',
          style: AppTheme.headlineMedium().copyWith(fontSize: 22),
        ),
      ),
      body: expensesAsync.when(
        data: (expenses) {
          if (expenses.isEmpty) {
            return const _EmptyExpenses();
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            itemCount: expenses.length,
            itemBuilder: (context, index) {
              final expense = expenses[index];
              return _ExpenseCard(
                expense: expense,
                currency: currency,
                currencyCode: currencyCode,
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
            'Error loading expenses: $e',
            style: AppTheme.bodyMedium(color: AppTheme.errorRed),
          ),
        ),
      ),
    );
  }
}

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.emerald.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: AppTheme.emerald,
            ),
          ),
          const SizedBox(height: 24),
          Text('Track your first expense', style: AppTheme.titleLarge()),
          const SizedBox(height: 12),
          Text(
            'Add expenses manually or scan a receipt to keep your tax report current.',
            style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.emerald,
                foregroundColor: AppTheme.bgDeep,
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add expense'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseCard extends ConsumerWidget {
  const _ExpenseCard({
    required this.expense,
    required this.currency,
    required this.currencyCode,
  });
  final Expense expense;
  final String currency;
  final String currencyCode;

  void _showDetails(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ExpenseDetailsModal(
        expense: expense,
        currency: currency,
        currencyCode: currencyCode,
        ref: ref,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasImage =
        expense.receiptImagePath != null &&
        File(expense.receiptImagePath!).existsSync();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey(expense.id),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: AppTheme.errorRed.withAlpha(200),
            borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        confirmDismiss: (direction) async {
          return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: AppTheme.bgCard,
              title: Text('Delete Expense', style: AppTheme.headlineMedium()),
              content: Text(
                'Are you sure you want to delete this expense?',
                style: AppTheme.bodyMedium(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Cancel',
                    style: AppTheme.bodyMedium(color: AppTheme.textHint),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    'Delete',
                    style: AppTheme.bodyMedium(color: AppTheme.errorRed),
                  ),
                ),
              ],
            ),
          );
        },
        onDismissed: (_) {
          ref.read(expenseActionsProvider).deleteExpense(expense.id);
        },
        child: InkWell(
          onTap: () => _showDetails(context, ref),
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.receipt_outlined,
                        color: AppTheme.emerald,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                expense.category.label,
                                style: AppTheme.bodyLarge(),
                              ),
                              Text(
                                formatCurrency(
                                  expense.amount,
                                  currency,
                                  currencyCode: currencyCode,
                                ),
                                style: AppTheme.titleLarge(
                                  color: AppTheme.emerald,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 14,
                                color: AppTheme.textHint,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                formatDate(expense.date),
                                style: AppTheme.labelSmall(
                                  color: AppTheme.textHint,
                                ),
                              ),
                              if (hasImage) ...[
                                const SizedBox(width: 12),
                                const Icon(
                                  Icons.image_outlined,
                                  size: 14,
                                  color: AppTheme.emerald,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Receipt',
                                  style: AppTheme.labelSmall(
                                    color: AppTheme.emerald,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (expense.note.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              expense.note,
                              style: AppTheme.bodyMedium(
                                color: AppTheme.textSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: AppTheme.glassBorder, height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    InkWell(
                      onTap: () => _showDetails(context, ref),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.remove_red_eye_outlined,
                              size: 16,
                              color: AppTheme.emerald,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Preview',
                              style:
                                  AppTheme.bodyMedium(
                                    color: AppTheme.emerald,
                                  ).copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AddExpenseScreen(existingExpense: expense),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Modify',
                              style: AppTheme.bodyMedium(color: Colors.white70)
                                  .copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
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
        ),
      ),
    );
  }
}

class _ExpenseDetailsModal extends StatelessWidget {
  const _ExpenseDetailsModal({
    required this.expense,
    required this.currency,
    required this.currencyCode,
    required this.ref,
  });

  final Expense expense;
  final String currency;
  final String currencyCode;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final imageFile = expense.receiptImagePath != null
        ? File(expense.receiptImagePath!)
        : null;
    final hasImage = imageFile != null && imageFile.existsSync();

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.emerald.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.receipt_outlined,
                      color: AppTheme.emerald,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    expense.category.label,
                    style: AppTheme.headlineMedium(),
                  ),
                ],
              ),
              Text(
                formatCurrency(
                  expense.amount,
                  currency,
                  currencyCode: currencyCode,
                ),
                style: AppTheme.headlineMedium().copyWith(
                  color: AppTheme.emerald,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: AppTheme.textHint,
              ),
              const SizedBox(width: 8),
              Text(
                formatDate(expense.date),
                style: AppTheme.bodyMedium(color: AppTheme.textHint),
              ),
            ],
          ),
          if (expense.note.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Details / Notes:',
              style: AppTheme.labelSmall(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Text(expense.note, style: AppTheme.bodyMedium()),
            ),
          ],
          if (hasImage) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Receipt Image:',
                  style: AppTheme.labelSmall(color: AppTheme.textSecondary),
                ),
                Text(
                  'Tap image for Full Screen',
                  style: AppTheme.labelSmall(color: AppTheme.emerald),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => _FullScreenImageViewer(imageFile: imageFile),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Image.file(
                        imageFile,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Container(
                        margin: const EdgeInsets.all(10),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(160),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.fullscreen_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Full Size',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.emerald,
                    foregroundColor: AppTheme.bgDeep,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                    ),
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text(
                    'Modify',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AddExpenseScreen(existingExpense: expense),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.errorRed.withAlpha(30),
                  padding: const EdgeInsets.all(14),
                ),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.errorRed,
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  ref.read(expenseActionsProvider).deleteExpense(expense.id);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  const _FullScreenImageViewer({required this.imageFile});
  final File imageFile;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(imageFile, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 50,
            right: 20,
            child: SafeArea(
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
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
    );
  }
}
