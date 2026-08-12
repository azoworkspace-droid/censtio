// GENERATED CODE — do not edit the annotation below.
// Run `flutter pub run build_runner build` to regenerate.
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../models/client.dart';
import '../models/expense.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';

part 'app_database.g.dart';

/// The single Drift database for the app.
@DriftDatabase(tables: [Clients, InvoiceItems, Invoices, InvoiceItemLinks, Expenses])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.addColumn(clients, clients.country);
          await m.addColumn(clients, clients.language);
          await m.addColumn(invoices, invoices.language);
        }
        if (from < 3) {
          await m.addColumn(invoices, invoices.template);
        }
        if (from < 4) {
          await m.addColumn(invoices, invoices.documentType);
        }
        if (from < 5) {
          await m.addColumn(invoices, invoices.paymentMethod);
        }
        if (from < 6) {
          await m.addColumn(invoices, invoices.notes);
        }
        if (from < 7) {
          await m.createTable(expenses);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static QueryExecutor _openConnection() {
    // drift_flutter picks the right SQLite backend per platform automatically.
    return driftDatabase(name: 'freelancer_db');
  }
}
