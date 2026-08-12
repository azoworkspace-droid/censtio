import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_service.dart';

/// Riverpod StateNotifier for managing the global reactive Default Tax Rate.
class DefaultTaxRateNotifier extends StateNotifier<double> {
  DefaultTaxRateNotifier() : super(0.0) {
    _load();
  }

  Future<void> _load() async {
    final saved = await SettingsService.getDefaultTaxRate();
    state = saved;
  }

  Future<void> setTaxRate(double newRate) async {
    state = newRate;
    await SettingsService.saveDefaultTaxRate(newRate);
  }
}

/// Global reactive default tax rate provider.
final defaultTaxRateProvider =
    StateNotifierProvider<DefaultTaxRateNotifier, double>((ref) {
      return DefaultTaxRateNotifier();
    });
