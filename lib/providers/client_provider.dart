import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_database.dart';
import '../services/database_service.dart';
import 'database_provider.dart';

/// Stream provider watching all saved clients in alphabetical order.
final clientListProvider = StreamProvider<List<Client>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return db.watchAllClients();
});

/// Exposes client CRUD operations.
final clientActionsProvider = Provider<ClientActions>((ref) {
  return ClientActions(ref.watch(databaseServiceProvider));
});

class ClientActions {
  const ClientActions(this._db);
  final DatabaseService _db;

  Future<int> addClient({
    required String name,
    String? address,
    String? taxId,
    String? phone,
    String? country,
    String? language,
  }) {
    return _db.insertClient(
      ClientsCompanion.insert(
        name: name,
        address: Value(address),
        taxId: Value(taxId),
        phone: Value(phone),
        country: Value(country),
        language: Value(language ?? 'English'),
      ),
    );
  }

  Future<bool> updateClient(ClientsCompanion entry) => _db.updateClient(entry);
  Future<int> deleteClient(int id) => _db.deleteClient(id);
}
