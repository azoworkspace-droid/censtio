import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database_service.dart';

/// Provides the global [DatabaseService] singleton to the Riverpod tree.
///
/// Using [Provider] (not [StateProvider] / [FutureProvider]) because
/// [DatabaseService] is a plain singleton — it manages its own internal state.
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService.instance;

  // Clean up the database connection when the provider is disposed.
  ref.onDispose(service.close);

  return service;
});
