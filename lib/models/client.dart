import 'package:drift/drift.dart';

/// Drift table definition for a Client.
class Clients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get address => text().nullable()();
  TextColumn get taxId => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get country => text().nullable()();
  TextColumn get language => text().nullable().withDefault(const Constant('English'))();
}
