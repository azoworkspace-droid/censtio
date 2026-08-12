import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLockMode { password, biometrics }

/// Stores and verifies the local app-lock credentials.
///
/// The password is never stored directly. The salt and SHA-256 verifier are
/// kept in Keychain/Keystore-backed secure storage.
class AppLockService {
  AppLockService._();

  static const _enabledKey = 'app_lock_enabled';
  static const _enabledPreferenceKey = 'app_lock_enabled_preference';
  static const _modePreferenceKey = 'app_lock_mode';
  static const _saltKey = 'app_lock_salt';
  static const _hashKey = 'app_lock_hash';

  static final _storage = FlutterSecureStorage();
  static final _localAuth = LocalAuthentication();
  static bool? _cachedEnabled;

  /// The gate listens to this notifier so Settings can request an immediate
  /// lock after the user enables protection.
  static final lockRequest = ValueNotifier<int>(0);

  static Future<bool> isEnabled() async {
    if (_cachedEnabled != null) return _cachedEnabled!;

    // Keep the non-sensitive switch state in SharedPreferences so Settings
    // never depends on a Keychain read just to render the page. Migrate the
    // old secure-storage flag once for users who enabled the lock previously.
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_enabledPreferenceKey);
    if (saved == true) {
      _cachedEnabled = true;
      return true;
    }

    // Repair an interrupted write from an older build. A false preference
    // must not hide a lock that was successfully stored in Keychain/Keystore.
    // Keep this bounded so Settings can never remain on its loading spinner.
    if (saved == false) {
      try {
        final secureState = await _storage
            .read(key: _enabledKey)
            .timeout(const Duration(milliseconds: 800));
        if (secureState == 'true') {
          await prefs.setBool(_enabledPreferenceKey, true);
          if (prefs.getString(_modePreferenceKey) == null) {
            await prefs.setString(
              _modePreferenceKey,
              AppLockMode.password.name,
            );
          }
          _cachedEnabled = true;
          return true;
        }
      } catch (error) {
        debugPrint('App-lock state repair skipped: $error');
      }
      _cachedEnabled = false;
      return false;
    }

    try {
      final legacy = await _storage
          .read(key: _enabledKey)
          .timeout(const Duration(seconds: 2));
      final enabled = legacy == 'true';
      await prefs.setBool(_enabledPreferenceKey, enabled);
      _cachedEnabled = enabled;
      if (enabled) {
        await prefs.setString(_modePreferenceKey, AppLockMode.password.name);
      }
      return enabled;
    } catch (error) {
      debugPrint('App-lock state migration failed: $error');
      await prefs.setBool(_enabledPreferenceKey, false);
      _cachedEnabled = false;
      return false;
    }
  }

  static Future<AppLockMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modePreferenceKey);
    return saved == AppLockMode.biometrics.name
        ? AppLockMode.biometrics
        : AppLockMode.password;
  }

  static Future<void> enable({
    required AppLockMode mode,
    String? password,
  }) async {
    if (mode == AppLockMode.password) {
      final value = password?.trim() ?? '';
      if (value.length < 4) {
        throw const FormatException(
          'Choose a password or PIN with at least 4 characters.',
        );
      }

      final saltBytes = List<int>.generate(
        32,
        (_) => Random.secure().nextInt(256),
      );
      final salt = base64UrlEncode(saltBytes);
      final hash = _hash(value, salt);

      await _storage.write(key: _saltKey, value: salt);
      await _storage.write(key: _hashKey, value: hash);
    } else {
      if (!await canUseBiometrics()) {
        throw const FormatException(
          'Face ID or Touch ID is not available on this device.',
        );
      }
      await _storage.delete(key: _saltKey);
      await _storage.delete(key: _hashKey);
    }

    await _storage.write(key: _enabledKey, value: 'true');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPreferenceKey, true);
    await prefs.setString(_modePreferenceKey, mode.name);
    _cachedEnabled = true;
  }

  static Future<void> disable() async {
    await _storage.delete(key: _enabledKey);
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _hashKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPreferenceKey, false);
    await prefs.remove(_modePreferenceKey);
    _cachedEnabled = false;
  }

  static Future<bool> verifyPassword(String password) async {
    final salt = await _storage.read(key: _saltKey);
    final expected = await _storage.read(key: _hashKey);
    if (salt == null || expected == null) return false;
    return _hash(password.trim(), salt) == expected;
  }

  static Future<bool> canUseBiometrics() async {
    try {
      if (!await _localAuth.isDeviceSupported()) return false;
      if (!await _localAuth.canCheckBiometrics) return false;
      return (await _localAuth.getAvailableBiometrics()).isNotEmpty;
    } catch (error) {
      debugPrint('Biometric capability check failed: $error');
      return false;
    }
  }

  static Future<bool> authenticateBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock your sensitive financial information',
        // Face ID/Touch ID is preferred, while the OS passcode remains a
        // recovery path if biometrics are temporarily unavailable.
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (error) {
      debugPrint('Biometric authentication failed: ${error.code}');
      return false;
    } catch (error) {
      debugPrint('Biometric authentication failed: $error');
      return false;
    }
  }

  static void requestLock() {
    lockRequest.value++;
  }

  static String _hash(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }
}
