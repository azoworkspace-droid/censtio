import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Privacy-safe analytics adapter used by the app.
///
/// The project does not currently configure a remote analytics provider, so
/// events are recorded locally with an allow-listed payload. The adapter keeps
/// the event contract ready for a future provider without ever accepting
/// names, tax numbers, bank details, or invoice content.
class AnalyticsService {
  AnalyticsService._();

  static const _eventsKey = 'analytics_event_log';
  static const _oncePrefix = 'analytics_once_';

  static const allowedEvents = <String>{
    'onboarding_started',
    'onboarding_step_viewed',
    'profile_type_selected',
    'business_name_completed',
    'currency_selected',
    'tax_type_selected',
    'payment_method_selected',
    'logo_upload_tapped',
    'onboarding_skipped',
    'onboarding_completed',
    'first_invoice_created',
    'first_expense_created',
    'invoice_created',
    'quote_created',
    'expense_created',
    'receipt_scan_started',
    'receipt_scan_completed',
    'invoice_scan_started',
    'invoice_scan_completed',
    'voice_invoice_started',
    'voice_expense_started',
    'paywall_viewed',
    'pro_paywall_viewed',
    'trial_started',
    'subscription_started',
    'subscription_cancelled',
    'export_clicked',
    'pdf_shared',
  };

  static Future<void> track(
    String event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {
    if (!allowedEvents.contains(event)) return;

    final safeProperties = <String, Object?>{};
    for (final entry in properties.entries) {
      final value = entry.value;
      if (value is String || value is num || value is bool) {
        safeProperties[entry.key] = value;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final events = prefs.getStringList(_eventsKey) ?? <String>[];
      events.add(
        jsonEncode({
          'event': event,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'properties': safeProperties,
        }),
      );
      if (events.length > 100) {
        events.removeRange(0, events.length - 100);
      }
      await prefs.setStringList(_eventsKey, events);
    } catch (error) {
      // Analytics must never block onboarding, invoicing, or payments.
      debugPrint('Analytics event could not be recorded: $error');
    }
  }

  static Future<void> trackOnce(
    String event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {
    if (!allowedEvents.contains(event)) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_oncePrefix$event';
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);
    await track(event, properties: properties);
  }
}
