import 'package:drift/drift.dart';

/// Category options for an [Expense].
enum ExpenseCategory {
  software,
  travel,
  office,
  marketing,
  meals,
  other;

  String get label {
    switch (this) {
      case ExpenseCategory.software:
        return 'Software';
      case ExpenseCategory.travel:
        return 'Travel';
      case ExpenseCategory.office:
        return 'Office';
      case ExpenseCategory.marketing:
        return 'Marketing';
      case ExpenseCategory.meals:
        return 'Meals';
      case ExpenseCategory.other:
        return 'Other';
    }
  }
}

/// Drift [TypeConverter] that persists [ExpenseCategory] as a String.
class ExpenseCategoryConverter
    extends TypeConverter<ExpenseCategory, String>
    with JsonTypeConverter2<ExpenseCategory, String, String> {
  const ExpenseCategoryConverter();

  @override
  ExpenseCategory fromSql(String fromDb) {
    return ExpenseCategory.values.firstWhere(
      (e) => e.name == fromDb,
      orElse: () => ExpenseCategory.other,
    );
  }

  @override
  String toSql(ExpenseCategory value) => value.name;

  @override
  ExpenseCategory fromJson(String json) => fromSql(json);

  @override
  String toJson(ExpenseCategory value) => toSql(value);
}

/// Drift table definition for an Expense.
///
/// Receipt images are stored as local file paths — the file itself lives on
/// device storage; only the path is persisted in SQLite.
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Expense amount (positive value).
  RealColumn get amount => real().withDefault(const Constant(0.0))();

  /// Category, stored as string via [ExpenseCategoryConverter].
  TextColumn get category => text()
      .map(const ExpenseCategoryConverter())
      .withDefault(const Constant('other'))();

  /// Date the expense was incurred, stored as epoch millis.
  DateTimeColumn get date => dateTime()();

  /// Optional note / description.
  TextColumn get note => text().withDefault(const Constant(''))();

  /// Absolute local path to a receipt photo image.
  /// Null when no receipt has been attached.
  TextColumn get receiptImagePath => text().nullable()();
}
