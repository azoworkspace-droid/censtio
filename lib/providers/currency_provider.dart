import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_service.dart';

/// Riverpod StateNotifier for managing the global reactive currency symbol.
class CurrencyNotifier extends StateNotifier<String> {
  CurrencyNotifier() : super('\$') {
    _load();
  }

  Future<void> _load() async {
    final saved = await SettingsService.getCurrencySymbol();
    state = saved;
  }

  Future<void> setCurrency(String newSymbol) async {
    final symbol = newSymbol.trim().isEmpty ? '\$' : newSymbol.trim();
    state = symbol;
    await SettingsService.saveCurrencySymbol(symbol);
  }
}

/// Global reactive currency symbol provider.
final currencySymbolProvider = StateNotifierProvider<CurrencyNotifier, String>((
  ref,
) {
  return CurrencyNotifier();
});

/// Reactive ISO currency code used for locale-aware formatting.
class CurrencyCodeNotifier extends StateNotifier<String> {
  CurrencyCodeNotifier() : super('USD') {
    _load();
  }

  Future<void> _load() async {
    state = await SettingsService.getCurrencyCode();
  }

  Future<void> setCurrencyCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return;
    state = normalized;
  }
}

final currencyCodeProvider =
    StateNotifierProvider<CurrencyCodeNotifier, String>((ref) {
      return CurrencyCodeNotifier();
    });
