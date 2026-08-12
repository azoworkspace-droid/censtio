import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freelancer/main.dart';
import 'package:freelancer/screens/onboarding_screen.dart';
import 'package:freelancer/services/settings_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Let any debounced draft write from the previous widget test finish
    // before clearing the shared in-memory store for the next test.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await SettingsService.clearOnboardingDraft();
  });

  testWidgets('FreelancerApp initializes smoke test', (
    WidgetTester tester,
  ) async {
    // Build our app wrapped in ProviderScope and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(child: FreelancerApp(showOnboarding: true)),
    );

    // Verify app renders onboarding screen title.
    expect(find.text('Welcome to Centsio AI: Invoice Maker'), findsOneWidget);
  });

  testWidgets('onboarding gates required fields and supports back navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: FreelancerApp(showOnboarding: true)),
    );
    await tester.pumpAndSettle();

    final continueButton = find.widgetWithText(ElevatedButton, 'Continue');
    expect(continueButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNotNull);

    await tester.tap(continueButton);
    await tester.pump();
    expect(
      find.text('Please enter your business name or full name.'),
      findsOneWidget,
    );

    final logoSkip = find.text('Skip for now');
    await tester.ensureVisible(logoSkip);
    await tester.tap(logoSkip);
    await tester.pump();
    expect(find.text('Logo skipped'), findsOneWidget);
    expect(find.text('You can add a logo later in Settings.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Acme Studio');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNotNull);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('Set up your invoice preferences'), findsOneWidget);

    await tester.tap(find.text('Select country / region'));
    await tester.pumpAndSettle();
    expect(find.text('Country / region').last, findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'United');
    await tester.pump();
    expect(find.text('United States'), findsOneWidget);
    await tester.tap(find.text('United States'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('USD · US Dollar (\$)'));
    await tester.pumpAndSettle();
    expect(find.text('Preferred currency').last, findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'EUR');
    await tester.pump();
    expect(find.text('EUR · Euro'), findsOneWidget);
    await tester.tap(find.text('EUR · Euro'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text('Payment details'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);
  });

  testWidgets('onboarding restores a partial draft', (
    WidgetTester tester,
  ) async {
    await SettingsService.saveOnboardingDraft(
      step: 1,
      profileType: 'Business',
      name: 'Restored Studio',
      tagline: 'Design services',
      countryCode: 'FR',
      currencyCode: 'EUR',
      taxIdLabel: 'SIRET',
      taxIdValue: 'optional-local-value',
      taxRate: '',
      paymentMethod: null,
      paymentDetails: '',
    );

    await tester.pumpWidget(
      const ProviderScope(child: FreelancerApp(showOnboarding: true)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('France · FR'), findsOneWidget);
    expect(find.text('EUR · Euro (€)'), findsOneWidget);
  });

  test('default tax rate accepts legacy numeric preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'default_tax_rate': 20.0,
    });

    expect(await SettingsService.getDefaultTaxRate(), 20.0);
  });
}
