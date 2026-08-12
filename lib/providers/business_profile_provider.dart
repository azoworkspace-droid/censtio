import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_service.dart';

/// Riverpod StateNotifier for managing the global reactive BusinessProfile state.
class BusinessProfileNotifier extends StateNotifier<BusinessProfile> {
  BusinessProfileNotifier() : super(BusinessProfile.defaultProfile) {
    refresh();
  }

  Future<void> refresh() async {
    final profile = await SettingsService.getBusinessProfile();
    state = profile;
  }
}

/// Global reactive business profile provider.
final businessProfileProvider =
    StateNotifierProvider<BusinessProfileNotifier, BusinessProfile>((ref) {
  return BusinessProfileNotifier();
});
