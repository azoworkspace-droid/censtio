import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/expense.dart';
import '../services/app_database.dart';
import '../services/revenuecat_service.dart';
import 'database_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Expense stream provider
// ═══════════════════════════════════════════════════════════════════════════════

/// Reactive stream of all expenses, newest first.
final expenseListProvider = StreamProvider<List<Expense>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return db.watchAllExpenses();
});

// ═══════════════════════════════════════════════════════════════════════════════
// Derived: total expense amount
// ═══════════════════════════════════════════════════════════════════════════════

/// Sum of all expense amounts. Rebuilds automatically when the expense list
/// changes.
///
/// UI usage:
/// ```dart
/// final totalAsync = ref.watch(totalExpensesProvider);
/// final total = totalAsync.value ?? 0.0;
/// ```
final totalExpensesProvider = Provider<AsyncValue<double>>((ref) {
  return ref
      .watch(expenseListProvider)
      .whenData(
        (expenses) => expenses.fold<double>(0.0, (sum, e) => sum + e.amount),
      );
});

// ═══════════════════════════════════════════════════════════════════════════════
// Expense CRUD actions
// ═══════════════════════════════════════════════════════════════════════════════

sealed class ExpenseCreationResult {
  const ExpenseCreationResult();
}

final class ExpenseCreated extends ExpenseCreationResult {
  const ExpenseCreated(this.expenseId);
  final int expenseId;
}

final class ExpenseFreemiumLimitReached extends ExpenseCreationResult {
  const ExpenseFreemiumLimitReached(this.usedCount);
  final int usedCount;
}

final expenseActionsProvider = Provider<ExpenseActions>((ref) {
  return ExpenseActions(ref);
});

class ExpenseActions {
  const ExpenseActions(this._ref);
  final Ref _ref;

  Future<int> addExpense({
    required double amount,
    required ExpenseCategory category,
    required DateTime date,
    required String note,
    String? receiptImagePath,
  }) {
    final db = _ref.read(databaseServiceProvider);
    return db.insertExpense(
      ExpensesCompanion.insert(
        amount: Value(amount),
        category: Value(category),
        date: date,
        note: Value(note),
        receiptImagePath: Value(receiptImagePath),
      ),
    );
  }

  /// Creates an expense only when the user still has a free creation
  /// available, or has an active PRO entitlement.
  Future<ExpenseCreationResult> addExpenseGated({
    required double amount,
    required ExpenseCategory category,
    required DateTime date,
    required String note,
    String? receiptImagePath,
  }) async {
    final db = _ref.read(databaseServiceProvider);
    final usedCount = await db.getBillableItemsThisMonth();
    final blocked = await RevenueCatService.hasReachedFreeLimit(usedCount);
    if (blocked) {
      return ExpenseFreemiumLimitReached(usedCount);
    }

    final expenseId = await db.insertExpense(
      ExpensesCompanion.insert(
        amount: Value(amount),
        category: Value(category),
        date: date,
        note: Value(note),
        receiptImagePath: Value(receiptImagePath),
      ),
    );
    return ExpenseCreated(expenseId);
  }

  Future<int> deleteExpense(int id) {
    final db = _ref.read(databaseServiceProvider);
    return db.deleteExpense(id);
  }

  Future<bool> updateExpense(Expense expense) {
    final db = _ref.read(databaseServiceProvider);
    return db.updateExpense(expense);
  }
}
