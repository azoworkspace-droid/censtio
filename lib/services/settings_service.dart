import 'package:shared_preferences/shared_preferences.dart';

/// Data class holding business branding & banking details.
class BusinessProfile {
  const BusinessProfile({
    required this.name,
    required this.tagline,
    this.profileType = 'Freelancer',
    this.country,
    this.address,
    this.taxId,
    this.bankDetails,
    this.logoPath,
    this.showPaymentDetailsOnInvoices = true,
  });

  final String name;
  final String tagline;
  final String profileType;
  final String? country;
  final String? address;
  final String? taxId;
  final String? bankDetails;
  final String? logoPath;
  final bool showPaymentDetailsOnInvoices;

  /// Default fallback profile when user has not configured custom branding yet.
  static const defaultProfile = BusinessProfile(
    name: 'Freelancer',
    tagline: 'Professional Invoicing Platform',
    profileType: 'Freelancer',
  );
}

/// A locally persisted, privacy-safe snapshot of an incomplete onboarding.
class OnboardingDraft {
  const OnboardingDraft({
    this.step = 0,
    this.profileType = 'Freelancer',
    this.name = '',
    this.tagline = '',
    this.logoPath,
    this.countryCode,
    this.currencyCode = 'USD',
    this.taxIdLabel,
    this.taxIdValue = '',
    this.taxRate = '',
    this.paymentMethod,
    this.paymentDetails = '',
  });

  final int step;
  final String profileType;
  final String name;
  final String tagline;
  final String? logoPath;
  final String? countryCode;
  final String currencyCode;
  final String? taxIdLabel;
  final String taxIdValue;
  final String taxRate;
  final String? paymentMethod;
  final String paymentDetails;
}

/// Service wrapping [SharedPreferences] for user branding & profile storage.
class SettingsService {
  SettingsService._();

  static const _keyName = 'business_name';
  static const _keyTagline = 'business_tagline';
  static const _keyProfileType = 'business_profile_type';
  static const _keyCountry = 'business_country';
  static const _keyAddress = 'business_address';
  static const _keyTaxId = 'business_tax_id';
  static const _keyBankDetails = 'business_bank_details';
  static const _keyLogoPath = 'business_logo_path';
  static const _keyShowPaymentDetails = 'show_payment_details_on_invoices';

  /// Loads saved business profile details from [SharedPreferences].
  static Future<BusinessProfile> getBusinessProfile() async {
    final prefs = await SharedPreferences.getInstance();

    final name = prefs.getString(_keyName) ?? 'Freelancer';
    final tagline =
        prefs.getString(_keyTagline) ?? 'Professional Invoicing Platform';
    final profileType = prefs.getString(_keyProfileType) ?? 'Freelancer';
    final country = prefs.getString(_keyCountry);
    final address = prefs.getString(_keyAddress);
    final taxId = prefs.getString(_keyTaxId);
    final bankDetails = prefs.getString(_keyBankDetails);
    final logoPath = prefs.getString(_keyLogoPath);
    final showPaymentDetails = prefs.getBool(_keyShowPaymentDetails) ?? true;

    return BusinessProfile(
      name: name.isEmpty ? 'Freelancer' : name,
      tagline: tagline.isEmpty ? 'Professional Invoicing Platform' : tagline,
      profileType: profileType.isEmpty ? 'Freelancer' : profileType,
      country: country?.isEmpty == true ? null : country,
      address: address?.isEmpty == true ? null : address,
      taxId: taxId?.isEmpty == true ? null : taxId,
      bankDetails: bankDetails?.isEmpty == true ? null : bankDetails,
      logoPath: logoPath?.isEmpty == true ? null : logoPath,
      showPaymentDetailsOnInvoices: showPaymentDetails,
    );
  }

  /// Saves updated business profile details to [SharedPreferences].
  static Future<void> saveBusinessProfile({
    required String name,
    required String tagline,
    String profileType = 'Freelancer',
    String? country,
    String? address,
    String? taxId,
    String? bankDetails,
    String? logoPath,
    bool showPaymentDetailsOnInvoices = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_keyName, name.trim());
    await prefs.setString(_keyTagline, tagline.trim());
    await prefs.setString(
      _keyProfileType,
      profileType.trim().isEmpty ? 'Freelancer' : profileType.trim(),
    );

    if (country != null && country.trim().isNotEmpty) {
      await prefs.setString(_keyCountry, country.trim());
    } else {
      await prefs.remove(_keyCountry);
    }

    if (address != null && address.trim().isNotEmpty) {
      await prefs.setString(_keyAddress, address.trim());
    } else {
      await prefs.remove(_keyAddress);
    }

    if (taxId != null && taxId.trim().isNotEmpty) {
      await prefs.setString(_keyTaxId, taxId.trim());
    } else {
      await prefs.remove(_keyTaxId);
    }

    if (bankDetails != null && bankDetails.trim().isNotEmpty) {
      await prefs.setString(_keyBankDetails, bankDetails.trim());
    } else {
      await prefs.remove(_keyBankDetails);
    }

    if (logoPath != null && logoPath.trim().isNotEmpty) {
      await prefs.setString(_keyLogoPath, logoPath.trim());
    } else {
      await prefs.remove(_keyLogoPath);
    }
    await prefs.setBool(_keyShowPaymentDetails, showPaymentDetailsOnInvoices);
  }

  static Future<bool> getShowPaymentDetailsOnInvoices() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowPaymentDetails) ?? true;
  }

  static const _keyOnboardingCompleted = 'has_completed_onboarding';
  static const _keyCurrencySymbol = 'currency_symbol';
  static const _keyCurrencyCode = 'currency_code';
  static const _keyTaxIdLabel = 'tax_id_label';
  static const _keyTaxIdValue = 'tax_id_value';
  static const _keyPaymentMethod = 'payment_method';
  static const _keyPaymentDetails = 'payment_details';

  /// Returns saved tax ID label (defaults to 'Tax ID').
  static Future<String> getTaxIdLabel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTaxIdLabel) ?? 'Tax ID';
  }

  /// Returns saved tax ID value.
  static Future<String> getTaxIdValue() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTaxIdValue) ?? '';
  }

  /// Saves both tax ID label & value to SharedPreferences.
  static Future<void> saveTaxIdDetails(String label, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanLabel = label.trim().isEmpty ? 'Tax ID' : label.trim();
    final cleanValue = value.trim();
    await prefs.setString(_keyTaxIdLabel, cleanLabel);
    if (cleanValue.isNotEmpty) {
      await prefs.setString(_keyTaxIdValue, cleanValue);
      await prefs.setString(_keyTaxId, '$cleanLabel: $cleanValue');
    } else {
      await prefs.remove(_keyTaxIdValue);
      await prefs.remove(_keyTaxId);
    }
  }

  /// Returns the saved currency symbol (defaults to '$').
  static Future<String> getCurrencySymbol() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCurrencySymbol) ?? '\$';
  }

  /// Saves the currency symbol to [SharedPreferences].
  static Future<void> saveCurrencySymbol(String symbol) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyCurrencySymbol,
      symbol.trim().isEmpty ? '\$' : symbol.trim(),
    );
  }

  /// Saves the ISO code and the existing symbol value used by invoice/PDF
  /// formatting. Keeping both avoids breaking existing invoice rendering.
  static Future<void> saveCurrencySelection({
    required String code,
    required String symbol,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrencyCode, code.trim().toUpperCase());
    await prefs.setString(
      _keyCurrencySymbol,
      symbol.trim().isEmpty ? r'$' : symbol.trim(),
    );
  }

  static Future<String> getCurrencyCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCurrencyCode) ?? 'USD';
  }

  static Future<void> savePaymentSelection({
    String? method,
    String? details,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (method != null && method.trim().isNotEmpty) {
      await prefs.setString(_keyPaymentMethod, method.trim());
    } else {
      await prefs.remove(_keyPaymentMethod);
    }
    if (details != null && details.trim().isNotEmpty) {
      await prefs.setString(_keyPaymentDetails, details.trim());
    } else {
      await prefs.remove(_keyPaymentDetails);
    }
  }

  static Future<String?> getPaymentMethod() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPaymentMethod);
  }

  static Future<String> getPaymentDetails() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPaymentDetails) ?? '';
  }

  static const _keyDefaultTaxRate = 'default_tax_rate';

  /// Returns the saved default tax rate. Zero means no tax configured yet.
  static Future<double> getDefaultTaxRate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(_keyDefaultTaxRate);
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim()) ?? 0.0;
    return 0.0;
  }

  /// Saves the default tax rate to [SharedPreferences].
  static Future<void> saveDefaultTaxRate(double rate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDefaultTaxRate, rate);
  }

  /// Returns true if the user has completed initial onboarding.
  static Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingCompleted) ?? false;
  }

  /// Sets the onboarding completion flag to true.
  static Future<void> setOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingCompleted, true);
  }

  static const _keyOnboardingStep = 'onboarding_draft_step';
  static const _keyOnboardingProfileType = 'onboarding_draft_profile_type';
  static const _keyOnboardingName = 'onboarding_draft_name';
  static const _keyOnboardingTagline = 'onboarding_draft_tagline';
  static const _keyOnboardingLogoPath = 'onboarding_draft_logo_path';
  static const _keyOnboardingCountry = 'onboarding_draft_country';
  static const _keyOnboardingCurrency = 'onboarding_draft_currency';
  static const _keyOnboardingTaxLabel = 'onboarding_draft_tax_label';
  static const _keyOnboardingTaxValue = 'onboarding_draft_tax_value';
  static const _keyOnboardingTaxRate = 'onboarding_draft_tax_rate';
  static const _keyOnboardingPaymentMethod = 'onboarding_draft_payment_method';
  static const _keyOnboardingPaymentDetails =
      'onboarding_draft_payment_details';

  static Future<OnboardingDraft> getOnboardingDraft() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingDraft(
      step: (prefs.getInt(_keyOnboardingStep) ?? 0).clamp(0, 2).toInt(),
      profileType: prefs.getString(_keyOnboardingProfileType) ?? 'Freelancer',
      name: prefs.getString(_keyOnboardingName) ?? '',
      tagline: prefs.getString(_keyOnboardingTagline) ?? '',
      logoPath: prefs.getString(_keyOnboardingLogoPath),
      countryCode: prefs.getString(_keyOnboardingCountry),
      currencyCode: prefs.getString(_keyOnboardingCurrency) ?? 'USD',
      taxIdLabel: prefs.getString(_keyOnboardingTaxLabel),
      taxIdValue: prefs.getString(_keyOnboardingTaxValue) ?? '',
      taxRate: prefs.getString(_keyOnboardingTaxRate) ?? '',
      paymentMethod: prefs.getString(_keyOnboardingPaymentMethod),
      paymentDetails: prefs.getString(_keyOnboardingPaymentDetails) ?? '',
    );
  }

  static Future<void> saveOnboardingDraft({
    required int step,
    required String profileType,
    required String name,
    required String tagline,
    String? logoPath,
    String? countryCode,
    required String currencyCode,
    String? taxIdLabel,
    required String taxIdValue,
    required String taxRate,
    String? paymentMethod,
    required String paymentDetails,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyOnboardingStep, step.clamp(0, 2).toInt());
    await prefs.setString(_keyOnboardingProfileType, profileType);
    await prefs.setString(_keyOnboardingName, name);
    await prefs.setString(_keyOnboardingTagline, tagline);
    await _setOptionalString(prefs, _keyOnboardingLogoPath, logoPath);
    await _setOptionalString(prefs, _keyOnboardingCountry, countryCode);
    await prefs.setString(_keyOnboardingCurrency, currencyCode);
    await _setOptionalString(prefs, _keyOnboardingTaxLabel, taxIdLabel);
    await prefs.setString(_keyOnboardingTaxValue, taxIdValue);
    await prefs.setString(_keyOnboardingTaxRate, taxRate);
    await _setOptionalString(prefs, _keyOnboardingPaymentMethod, paymentMethod);
    await prefs.setString(_keyOnboardingPaymentDetails, paymentDetails);
  }

  static Future<void> clearOnboardingDraft() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _keyOnboardingStep,
      _keyOnboardingProfileType,
      _keyOnboardingName,
      _keyOnboardingTagline,
      _keyOnboardingLogoPath,
      _keyOnboardingCountry,
      _keyOnboardingCurrency,
      _keyOnboardingTaxLabel,
      _keyOnboardingTaxValue,
      _keyOnboardingTaxRate,
      _keyOnboardingPaymentMethod,
      _keyOnboardingPaymentDetails,
    ]) {
      await prefs.remove(key);
    }
  }

  static Future<void> _setOptionalString(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value != null && value.trim().isNotEmpty) {
      await prefs.setString(key, value.trim());
    } else {
      await prefs.remove(key);
    }
  }
}
