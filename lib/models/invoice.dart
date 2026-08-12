import 'package:drift/drift.dart';

/// Enum representing the payment status of an Invoice.
/// Stored as a TEXT value in SQLite.
enum InvoiceStatus { paid, pending, overdue, draft, cancelled, none }

extension InvoiceStatusCopy on InvoiceStatus {
  String get displayName => switch (this) {
    InvoiceStatus.paid => 'Paid',
    InvoiceStatus.pending => 'Pending',
    InvoiceStatus.overdue => 'Overdue',
    InvoiceStatus.draft => 'Draft',
    InvoiceStatus.cancelled => 'Cancelled',
    InvoiceStatus.none => 'Unspecified',
  };
}

/// A Drift TypeConverter that persists [InvoiceStatus] as a String.
class InvoiceStatusConverter extends TypeConverter<InvoiceStatus, String>
    with JsonTypeConverter2<InvoiceStatus, String, String> {
  const InvoiceStatusConverter();

  @override
  InvoiceStatus fromSql(String fromDb) {
    return InvoiceStatus.values.firstWhere(
      (e) => e.name == fromDb,
      orElse: () => InvoiceStatus.pending,
    );
  }

  @override
  String toSql(InvoiceStatus value) => value.name;

  @override
  InvoiceStatus fromJson(String json) => fromSql(json);

  @override
  String toJson(InvoiceStatus value) => toSql(value);
}

/// Drift table definition for an Invoice.
///
/// Items are stored in a separate [InvoiceItems] table and linked via
/// the join table [InvoiceItemLinks].
class Invoices extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Human-readable invoice number, e.g. "INV-0042".
  TextColumn get invoiceNumber => text().withLength(min: 1, max: 50)();

  /// Issue date stored as epoch milliseconds.
  DateTimeColumn get date => dateTime()();

  /// Foreign key referencing [Clients].
  IntColumn get clientId => integer()();

  /// Pre-calculated total (items × quantity + tax).
  RealColumn get totalAmount => real().withDefault(const Constant(0.0))();

  /// Tax rate as a percentage, e.g. 20.0 for 20%.
  RealColumn get taxRate => real().withDefault(const Constant(0.0))();

  /// Payment status stored as a text value via [InvoiceStatusConverter].
  TextColumn get status => text()
      .map(const InvoiceStatusConverter())
      .withDefault(const Constant('pending'))();

  /// Language for PDF generation (e.g. 'English', 'Français', 'Español').
  TextColumn get language =>
      text().nullable().withDefault(const Constant('English'))();

  /// Invoice template design ('Basic', 'Modern', 'Elite').
  TextColumn get template =>
      text().nullable().withDefault(const Constant('Basic'))();

  /// Document type ('invoice' or 'quote').
  TextColumn get documentType =>
      text().nullable().withDefault(const Constant('invoice'))();

  /// Payment method ('Bank Transfer', 'Cash', 'Check', 'Credit Card', 'Other').
  TextColumn get paymentMethod =>
      text().nullable().withDefault(const Constant('Bank Transfer'))();

  /// Custom footer note or thank you message printed on PDF.
  TextColumn get notes => text().nullable()();
}

/// Join table that maps many-to-many between [Invoices] and [InvoiceItems].
class InvoiceItemLinks extends Table {
  IntColumn get invoiceId => integer()();
  IntColumn get invoiceItemId => integer()();

  @override
  Set<Column> get primaryKey => {invoiceId, invoiceItemId};
}
