import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../models/invoice.dart'; // for InvoiceStatus enum
import '../models/expense.dart';
import 'app_database.dart';

/// High-level service that wraps [AppDatabase] and exposes clean CRUD methods
/// for Clients, InvoiceItems, and Invoices.
///
/// Usage (singleton pattern):
/// ```dart
/// final db = DatabaseService.instance;
/// final clients = await db.getAllClients();
/// ```
class DatabaseService {
  DatabaseService._internal(this._db);

  static DatabaseService? _instance;

  /// Returns the global singleton instance.
  static DatabaseService get instance {
    _instance ??= DatabaseService._internal(AppDatabase());
    return _instance!;
  }

  final AppDatabase _db;

  // ---------------------------------------------------------------------------
  // CLIENT CRUD
  // ---------------------------------------------------------------------------

  /// Returns a stream of all clients, ordered by name.
  Stream<List<Client>> watchAllClients() => (_db.select(
    _db.clients,
  )..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  /// Returns a one-time list of all clients.
  Future<List<Client>> getAllClients() => (_db.select(
    _db.clients,
  )..orderBy([(c) => OrderingTerm.asc(c.name)])).get();

  /// Returns a single client by [id], or `null` if not found.
  Future<Client?> getClientById(int id) => (_db.select(
    _db.clients,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Inserts a new client and returns its generated id.
  Future<int> insertClient(ClientsCompanion entry) =>
      _db.into(_db.clients).insert(entry);

  /// Updates an existing client. Returns the number of rows affected.
  Future<bool> updateClient(ClientsCompanion entry) =>
      _db.update(_db.clients).replace(entry);

  /// Deletes a client by [id].
  Future<int> deleteClient(int id) =>
      (_db.delete(_db.clients)..where((c) => c.id.equals(id))).go();

  // ---------------------------------------------------------------------------
  // INVOICE ITEM CRUD
  // ---------------------------------------------------------------------------

  /// Returns all invoice items as a one-time list.
  Future<List<InvoiceItem>> getAllInvoiceItems() =>
      _db.select(_db.invoiceItems).get();

  /// Returns all items linked to a specific invoice.
  Future<List<InvoiceItem>> getItemsForInvoice(int invoiceId) async {
    final links = await (_db.select(
      _db.invoiceItemLinks,
    )..where((l) => l.invoiceId.equals(invoiceId))).get();
    if (links.isEmpty) return [];
    final itemIds = links.map((l) => l.invoiceItemId).toList();
    return (_db.select(
      _db.invoiceItems,
    )..where((i) => i.id.isIn(itemIds))).get();
  }

  /// Returns a single invoice item by [id], or `null` if not found.
  Future<InvoiceItem?> getInvoiceItemById(int id) => (_db.select(
    _db.invoiceItems,
  )..where((i) => i.id.equals(id))).getSingleOrNull();

  /// Inserts a new invoice item and returns its generated id.
  Future<int> insertInvoiceItem(InvoiceItemsCompanion entry) =>
      _db.into(_db.invoiceItems).insert(entry);

  /// Updates an existing invoice item.
  Future<bool> updateInvoiceItem(InvoiceItemsCompanion entry) =>
      _db.update(_db.invoiceItems).replace(entry);

  /// Deletes an invoice item by [id] and removes any join-table links.
  Future<void> deleteInvoiceItem(int id) async {
    await (_db.delete(
      _db.invoiceItemLinks,
    )..where((l) => l.invoiceItemId.equals(id))).go();
    await (_db.delete(_db.invoiceItems)..where((i) => i.id.equals(id))).go();
  }

  // ---------------------------------------------------------------------------
  // INVOICE CRUD
  // ---------------------------------------------------------------------------

  /// Returns a stream of all invoices, newest first.
  Stream<List<Invoice>> watchAllInvoices() => (_db.select(
    _db.invoices,
  )..orderBy([(inv) => OrderingTerm.desc(inv.date)])).watch();

  /// Returns a one-time list of all invoices, newest first.
  Future<List<Invoice>> getAllInvoices() => (_db.select(
    _db.invoices,
  )..orderBy([(inv) => OrderingTerm.desc(inv.date)])).get();

  /// Returns invoices filtered by [status].
  Future<List<Invoice>> getInvoicesByStatus(InvoiceStatus status) =>
      (_db.select(_db.invoices)
            ..where((inv) => inv.status.equals(status.name))
            ..orderBy([(inv) => OrderingTerm.desc(inv.date)]))
          .get();

  /// Returns the number of invoices whose [Invoice.date] falls in the current
  /// calendar month. Used to enforce the free-tier limit of 3 invoices/month.
  Future<int> getInvoicesThisMonth() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month);
    final startOfNextMonth = DateTime(now.year, now.month + 1);
    final result =
        await (_db.select(_db.invoices)..where(
              (inv) => inv.date.isBetweenValues(startOfMonth, startOfNextMonth),
            ))
            .get();
    return result.length;
  }

  /// Returns the combined number of invoices, quotes, and expenses dated in
  /// the current calendar month.
  ///
  /// Quotes are stored in the invoices table with `documentType == 'quote'`,
  /// so they are intentionally included in the invoice query.
  Future<int> getBillableItemsThisMonth() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month);
    final startOfNextMonth = DateTime(now.year, now.month + 1);

    final invoices =
        await (_db.select(_db.invoices)..where(
              (invoice) =>
                  invoice.date.isBetweenValues(startOfMonth, startOfNextMonth),
            ))
            .get();
    final expenses =
        await (_db.select(_db.expenses)..where(
              (expense) =>
                  expense.date.isBetweenValues(startOfMonth, startOfNextMonth),
            ))
            .get();

    return invoices.length + expenses.length;
  }

  /// Generates a sequential document number for the current year in the format:
  /// `PREFIX-YYYY-XXX` (e.g. `INV-2026-003` or `DEV-2026-001`).
  Future<String> generateNextInvoiceNumber({String prefix = 'INV'}) async {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year);
    final startOfNextYear = DateTime(now.year + 1);

    final invoicesThisYear =
        await (_db.select(_db.invoices)..where(
              (inv) => inv.date.isBetweenValues(startOfYear, startOfNextYear),
            ))
            .get();

    final nextIndex = invoicesThisYear.length + 1;
    final formattedIndex = nextIndex.toString().padLeft(3, '0');
    return '$prefix-${now.year}-$formattedIndex';
  }

  /// Returns a single invoice by [id], or `null` if not found.
  Future<Invoice?> getInvoiceById(int id) => (_db.select(
    _db.invoices,
  )..where((inv) => inv.id.equals(id))).getSingleOrNull();

  /// Inserts a new invoice with its [items] in a single transaction.
  ///
  /// Returns the generated invoice id.
  Future<int> insertInvoice(
    InvoicesCompanion entry,
    List<InvoiceItemsCompanion> items,
  ) async {
    return _db.transaction(() async {
      final invoiceId = await _db.into(_db.invoices).insert(entry);

      for (final item in items) {
        final itemId = await _db.into(_db.invoiceItems).insert(item);
        await _db
            .into(_db.invoiceItemLinks)
            .insert(
              InvoiceItemLinksCompanion.insert(
                invoiceId: invoiceId,
                invoiceItemId: itemId,
              ),
            );
      }

      return invoiceId;
    });
  }

  /// Updates an invoice's header fields (supports partial updates via companion).
  Future<int> updateInvoice(InvoicesCompanion entry) {
    return (_db.update(
      _db.invoices,
    )..where((i) => i.id.equals(entry.id.value))).write(entry);
  }

  /// Updates an invoice's payment status.
  Future<int> updateInvoiceStatus(int invoiceId, InvoiceStatus status) {
    return (_db.update(_db.invoices)..where((i) => i.id.equals(invoiceId)))
        .write(InvoicesCompanion(status: Value(status)));
  }

  /// Replaces all line items for [invoiceId] with [newItems] in a transaction.
  Future<void> replaceInvoiceItems(
    int invoiceId,
    List<InvoiceItemsCompanion> newItems,
  ) async {
    await _db.transaction(() async {
      // Remove existing links (items themselves may be shared; only delete
      // items that belong solely to this invoice if desired — for simplicity
      // here we delete linked items outright).
      final oldLinks = await (_db.select(
        _db.invoiceItemLinks,
      )..where((l) => l.invoiceId.equals(invoiceId))).get();
      for (final link in oldLinks) {
        await (_db.delete(
          _db.invoiceItems,
        )..where((i) => i.id.equals(link.invoiceItemId))).go();
      }
      await (_db.delete(
        _db.invoiceItemLinks,
      )..where((l) => l.invoiceId.equals(invoiceId))).go();

      // Insert replacement items.
      for (final item in newItems) {
        final itemId = await _db.into(_db.invoiceItems).insert(item);
        await _db
            .into(_db.invoiceItemLinks)
            .insert(
              InvoiceItemLinksCompanion.insert(
                invoiceId: invoiceId,
                invoiceItemId: itemId,
              ),
            );
      }
    });
  }

  /// Deletes an invoice and all its linked items in a single transaction.
  Future<void> deleteInvoice(int id) async {
    await _db.transaction(() async {
      final links = await (_db.select(
        _db.invoiceItemLinks,
      )..where((l) => l.invoiceId.equals(id))).get();
      for (final link in links) {
        await (_db.delete(
          _db.invoiceItems,
        )..where((i) => i.id.equals(link.invoiceItemId))).go();
      }
      await (_db.delete(
        _db.invoiceItemLinks,
      )..where((l) => l.invoiceId.equals(id))).go();
      await (_db.delete(_db.invoices)..where((inv) => inv.id.equals(id))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // EXPENSE CRUD
  // ---------------------------------------------------------------------------

  /// Returns a reactive stream of all expenses, newest first.
  Stream<List<Expense>> watchAllExpenses() => (_db.select(
    _db.expenses,
  )..orderBy([(e) => OrderingTerm.desc(e.date)])).watch();

  /// One-time snapshot of all expenses.
  Future<List<Expense>> getAllExpenses() => (_db.select(
    _db.expenses,
  )..orderBy([(e) => OrderingTerm.desc(e.date)])).get();

  /// Inserts a new expense. Returns the generated id.
  Future<int> insertExpense(ExpensesCompanion entry) =>
      _db.into(_db.expenses).insert(entry);

  /// Deletes an expense by [id].
  Future<int> deleteExpense(int id) =>
      (_db.delete(_db.expenses)..where((e) => e.id.equals(id))).go();

  /// Creates a JSON-safe local snapshot for an explicit user export action.
  /// Sensitive values never go to analytics; they only enter the user-chosen
  /// system share sheet.
  Future<Map<String, Object?>> exportSnapshot() async {
    final clients = await getAllClients();
    final invoices = await getAllInvoices();
    final expenses = await getAllExpenses();
    final invoiceItems = <Map<String, Object?>>[];
    for (final invoice in invoices) {
      final items = await getItemsForInvoice(invoice.id);
      for (final item in items) {
        invoiceItems.add({
          'invoiceId': invoice.id,
          'description': item.description,
          'unitPrice': item.unitPrice,
          'quantity': item.quantity,
        });
      }
    }
    return {
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'clients': [
        for (final client in clients)
          {
            'id': client.id,
            'name': client.name,
            'address': client.address,
            'taxId': client.taxId,
            'phone': client.phone,
            'country': client.country,
            'language': client.language,
          },
      ],
      'invoices': [
        for (final invoice in invoices)
          {
            'id': invoice.id,
            'invoiceNumber': invoice.invoiceNumber,
            'date': invoice.date.toIso8601String(),
            'clientId': invoice.clientId,
            'totalAmount': invoice.totalAmount,
            'taxRate': invoice.taxRate,
            'status': invoice.status.name,
            'language': invoice.language,
            'template': invoice.template,
            'documentType': invoice.documentType,
            'paymentMethod': invoice.paymentMethod,
            'notes': invoice.notes,
          },
      ],
      'invoiceItems': invoiceItems,
      'expenses': [
        for (final expense in expenses)
          {
            'id': expense.id,
            'amount': expense.amount,
            'category': expense.category.name,
            'date': expense.date.toIso8601String(),
            'note': expense.note,
            'receiptImagePath': expense.receiptImagePath,
          },
      ],
    };
  }

  /// Imports a snapshot created by [exportSnapshot]. Existing data is kept;
  /// imported records receive fresh local IDs and are safe to undo by deleting
  /// the imported records from the normal list screens.
  Future<void> importSnapshot(Map<String, dynamic> snapshot) async {
    final clients = snapshot['clients'];
    final invoices = snapshot['invoices'];
    final invoiceItems = snapshot['invoiceItems'];
    final expenses = snapshot['expenses'];
    if (clients is! List || invoices is! List || expenses is! List) {
      throw const FormatException('Invalid workspace export.');
    }

    await _db.transaction(() async {
      final clientIds = <int, int>{};
      for (final raw in clients) {
        if (raw is! Map) continue;
        final name = raw['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final newId = await insertClient(
          ClientsCompanion.insert(
            name: name,
            address: Value(_nullableString(raw['address'])),
            taxId: Value(_nullableString(raw['taxId'])),
            phone: Value(_nullableString(raw['phone'])),
            country: Value(_nullableString(raw['country'])),
            language: Value(raw['language']?.toString() ?? 'English'),
          ),
        );
        final oldId = _intValue(raw['id']);
        if (oldId != null) clientIds[oldId] = newId;
      }

      final invoiceIds = <int, int>{};
      for (final raw in invoices) {
        if (raw is! Map) continue;
        final oldClientId = _intValue(raw['clientId']);
        final clientId = oldClientId == null ? null : clientIds[oldClientId];
        if (clientId == null) continue;
        final documentType = raw['documentType']?.toString() ?? 'invoice';
        final invoiceId = await insertInvoice(
          InvoicesCompanion.insert(
            invoiceNumber:
                raw['invoiceNumber']?.toString() ??
                'IMP-${DateTime.now().millisecondsSinceEpoch}',
            date: _dateValue(raw['date']),
            clientId: clientId,
            totalAmount: Value(_doubleValue(raw['totalAmount'])),
            taxRate: Value(_doubleValue(raw['taxRate'])),
            status: Value(_statusValue(raw['status'])),
            language: Value(raw['language']?.toString() ?? 'English'),
            template: Value(raw['template']?.toString() ?? 'Basic'),
            documentType: Value(documentType),
            paymentMethod: Value(raw['paymentMethod']?.toString() ?? 'Other'),
            notes: Value(_nullableString(raw['notes'])),
          ),
          const [],
        );
        final oldId = _intValue(raw['id']);
        if (oldId != null) invoiceIds[oldId] = invoiceId;
      }

      if (invoiceItems is List) {
        for (final raw in invoiceItems) {
          if (raw is! Map) continue;
          final invoiceId = invoiceIds[_intValue(raw['invoiceId'])];
          final description = raw['description']?.toString().trim() ?? '';
          if (invoiceId == null || description.isEmpty) continue;
          final itemId = await insertInvoiceItem(
            InvoiceItemsCompanion.insert(
              description: description,
              unitPrice: _doubleValue(raw['unitPrice']),
              quantity: Value(math.max(1, _intValue(raw['quantity']) ?? 1)),
            ),
          );
          await _db
              .into(_db.invoiceItemLinks)
              .insert(
                InvoiceItemLinksCompanion.insert(
                  invoiceId: invoiceId,
                  invoiceItemId: itemId,
                ),
              );
        }
      }

      for (final raw in expenses) {
        if (raw is! Map) continue;
        await insertExpense(
          ExpensesCompanion.insert(
            amount: Value(_doubleValue(raw['amount'])),
            category: Value(_categoryValue(raw['category'])),
            date: _dateValue(raw['date']),
            note: Value(raw['note']?.toString() ?? ''),
            receiptImagePath: Value(_nullableString(raw['receiptImagePath'])),
          ),
        );
      }
    });
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _intValue(Object? value) => int.tryParse(value?.toString() ?? '');

  static double _doubleValue(Object? value) =>
      double.tryParse(value?.toString() ?? '') ?? 0.0;

  static DateTime _dateValue(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();

  static InvoiceStatus _statusValue(Object? value) =>
      InvoiceStatus.values.firstWhere(
        (status) => status.name == value?.toString(),
        orElse: () => InvoiceStatus.draft,
      );

  static ExpenseCategory _categoryValue(Object? value) =>
      ExpenseCategory.values.firstWhere(
        (category) => category.name == value?.toString(),
        orElse: () => ExpenseCategory.other,
      );

  /// Deletes local business data after the UI has obtained confirmation.
  Future<void> deleteAllData() async {
    await _db.transaction(() async {
      await _db.delete(_db.invoiceItemLinks).go();
      await _db.delete(_db.invoiceItems).go();
      await _db.delete(_db.invoices).go();
      await _db.delete(_db.clients).go();
      await _db.delete(_db.expenses).go();
    });
  }

  /// Updates an existing expense. Returns true if updated.
  Future<bool> updateExpense(Expense expense) =>
      _db.update(_db.expenses).replace(expense);

  /// Closes the underlying database connection.
  Future<void> close() => _db.close();
}
