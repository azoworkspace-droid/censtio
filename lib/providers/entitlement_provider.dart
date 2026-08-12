import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;

import '../services/revenuecat_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Pro entitlement provider
// ═══════════════════════════════════════════════════════════════════════════════

/// Async snapshot of whether the current user holds the `pro_access` entitlement.
///
/// Backed by a [FutureProvider] so any widget that watches it rebuilds
/// automatically when [ref.invalidate(entitlementProvider)] is called after a
/// successful purchase or restore.
///
/// Usage:
/// ```dart
/// final proAsync = ref.watch(entitlementProvider);
/// final isPro = proAsync.value ?? false;
/// ```
final entitlementProvider = FutureProvider<bool>((ref) async {
  return RevenueCatService.isProUser();
});

// ═══════════════════════════════════════════════════════════════════════════════
// Convenience notifier — wraps purchase & restore and auto-invalidates
// ═══════════════════════════════════════════════════════════════════════════════

/// Encapsulates purchase-related mutations that must invalidate
/// [entitlementProvider] on success.
///
/// Usage:
/// ```dart
/// final purchaseActions = ref.read(purchaseActionsProvider);
/// final success = await purchaseActions.subscribe(package);
/// ```
final purchaseActionsProvider = Provider<PurchaseActions>((ref) {
  return PurchaseActions(ref);
});

class PurchaseActions {
  const PurchaseActions(this._ref);
  final Ref _ref;

  /// Triggers the OS purchase sheet for [package].
  ///
  /// Returns `true` if the purchase succeeded and the user now has pro access.
  Future<bool> subscribe(Package package) async {
    final info = await RevenueCatService.purchasePackage(package);
    if (info != null) {
      // Invalidate so all entitlement watchers rebuild.
      _ref.invalidate(entitlementProvider);
      return info.entitlements.active.containsKey(kProEntitlement);
    }
    return false;
  }

  /// Restores prior purchases.
  ///
  /// Returns `true` if the user now has pro access after restore.
  Future<bool> restore() async {
    final info = await RevenueCatService.restorePurchases();
    if (info != null) {
      _ref.invalidate(entitlementProvider);
      return info.entitlements.active.containsKey(kProEntitlement);
    }
    return false;
  }
}
