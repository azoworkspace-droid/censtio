import 'dart:io';

import 'package:flutter/foundation.dart';
// Alias the barrel import to avoid 'Package' colliding with dart:core.
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
// Import the specific types we use in return types / parameters.
import 'package:purchases_flutter/purchases_flutter.dart'
    show CustomerInfo, Offering, Package;

/// Identifier for the RevenueCat entitlement that unlocks pro features.
const String kProEntitlement = 'pro_access';

/// Product identifiers configured in App Store Connect / Google Play and
/// attached to the matching RevenueCat packages.
const String kMonthlyProductId = 'centsio_pro_monthly';
const String kAnnualProductId = 'centsio_pro_yearly';

/// How many billable records a free user may create per calendar month.
///
/// Invoices and quotes share the invoices table, so this limit applies to
/// invoices + quotes + expenses together.
const int kFreeCreationLimit = 3;

/// Kept for source compatibility with older callers.
@Deprecated('Use kFreeCreationLimit instead.')
const int kFreeInvoiceLimit = kFreeCreationLimit;

/// Wraps the RevenueCat SDK with a clean, testable interface.
///
/// ## Setup
/// 1. Replace [_iosApiKey] and [_androidApiKey] with your keys from the
///    RevenueCat dashboard → Project → API Keys.
/// 2. Call [RevenueCatService.init] from `main()` **before** `runApp`.
///
/// ## Entitlement
/// The service checks for the `"pro_access"` entitlement. Create a matching
/// entitlement in the RevenueCat dashboard and attach your products to it.
class RevenueCatService {
  RevenueCatService._();

  static bool _isConfigured = false;

  /// True only after RevenueCat has been successfully configured.
  ///
  /// All purchase-related callers use this guard so a missing key or a local
  /// test build cannot invoke an unconfigured native SDK.
  static bool get isConfigured => _isConfigured;

  // ── Replace with your real API keys ────────────────────────────────────────
  static const String _iosApiKey = 'appl_GKDOqBpDAjWeIqMretCAlildiKy';
  static const String _androidApiKey = 'goog_REPLACE_WITH_YOUR_ANDROID_KEY';

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Must be called once before using any other method.
  ///
  /// Typically invoked in `main()` after [WidgetsFlutterBinding.ensureInitialized].
  static Future<void> init() async {
    _isConfigured = false;
    try {
      // Enable verbose logging only in debug builds.
      await rc.Purchases.setLogLevel(
        kDebugMode ? rc.LogLevel.debug : rc.LogLevel.error,
      );

      final apiKey = Platform.isIOS ? _iosApiKey : _androidApiKey;
      if (apiKey.contains('REPLACE_WITH')) {
        debugPrint(
          '[RevenueCat] SDK initialization skipped; a real ${Platform.isIOS ? 'iOS' : 'Android'} API key is required.',
        );
        return;
      }

      final configuration = rc.PurchasesConfiguration(apiKey);
      await rc.Purchases.configure(configuration);
      _isConfigured = true;

      debugPrint('[RevenueCat] SDK configured.');
    } catch (e) {
      _isConfigured = false;
      debugPrint('[RevenueCat] Initialization failed: $e');
    }
  }

  // ── Entitlement ─────────────────────────────────────────────────────────────

  /// Returns `true` if the current user has an active `pro_access` entitlement.
  static Future<bool> isProUser() async {
    if (!_isConfigured) return false;

    try {
      final customerInfo = await rc.Purchases.getCustomerInfo();
      return customerInfo.entitlements.all[kProEntitlement]?.isActive == true;
    } catch (e) {
      debugPrint('[RevenueCat] isProUser error: $e');
      return false;
    }
  }

  /// Returns the latest [CustomerInfo] for the current user.
  static Future<CustomerInfo?> getCustomerInfo() async {
    if (!_isConfigured) return null;
    try {
      return await rc.Purchases.getCustomerInfo();
    } catch (e) {
      debugPrint('[RevenueCat] getCustomerInfo error: $e');
      return null;
    }
  }

  // ── Offerings & Purchase ───────────────────────────────────────────────────

  /// Fetches the current RevenueCat offering.
  ///
  /// Returns `null` if no offerings are configured in the dashboard yet,
  /// or if the network request fails.
  static Future<Offering?> getCurrentOffering() async {
    if (!_isConfigured) {
      debugPrint('[RevenueCat] Offerings skipped; SDK is not configured.');
      return null;
    }
    try {
      final offerings = await rc.Purchases.getOfferings();
      return offerings.current;
    } catch (e) {
      debugPrint('[RevenueCat] getOfferings error: $e');
      return null;
    }
  }

  /// Initiates the OS-native purchase flow for the given [package].
  ///
  /// Returns the updated [CustomerInfo] on success, or `null` if the user
  /// cancelled or the purchase failed.
  static Future<CustomerInfo?> purchasePackage(Package package) async {
    if (!_isConfigured) {
      debugPrint('[RevenueCat] Purchase skipped; SDK is not configured.');
      return null;
    }
    try {
      final result = await rc.Purchases.purchase(
        rc.PurchaseParams.package(package),
      );
      final info = result.customerInfo;
      debugPrint(
        '[RevenueCat] Purchase succeeded: ${info.entitlements.active.keys}',
      );
      return info;
    } catch (e) {
      debugPrint('[RevenueCat] purchasePackage error: $e');
      return null;
    }
  }

  /// Restores previously purchased subscriptions for the current user.
  ///
  /// Returns the restored [CustomerInfo], or `null` on failure.
  static Future<CustomerInfo?> restorePurchases() async {
    if (!_isConfigured) {
      debugPrint('[RevenueCat] Restore skipped; SDK is not configured.');
      return null;
    }
    try {
      final info = await rc.Purchases.restorePurchases();
      debugPrint(
        '[RevenueCat] Restore complete: ${info.entitlements.active.keys}',
      );
      return info;
    } catch (e) {
      debugPrint('[RevenueCat] restorePurchases error: $e');
      return null;
    }
  }

  // ── Freemium gate ─────────────────────────────────────────────────────────

  /// Returns `true` when a free user has reached [kFreeCreationLimit] this month.
  ///
  /// Always returns `false` for pro users (no limit applies).
  static Future<bool> hasReachedFreeLimit(int creationsThisMonth) async {
    if (creationsThisMonth < kFreeCreationLimit) return false;
    // Short-circuit: check entitlement only when limit is hit.
    final isPro = await isProUser();
    return !isPro;
  }
}
