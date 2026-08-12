import 'package:drift/drift.dart';

/// Drift table definition for a line-item on an invoice.
class InvoiceItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get description => text().withLength(min: 1, max: 500)();
  RealColumn get unitPrice => real()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
}
