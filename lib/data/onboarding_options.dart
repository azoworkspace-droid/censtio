/// Catalogs used by onboarding and other profile surfaces.
///
/// These values intentionally stay local to the app. They are presentation
/// data, not tax advice or a validation authority for a user's jurisdiction.
class CurrencyOption {
  const CurrencyOption({
    required this.code,
    required this.name,
    required this.symbol,
  });

  final String code;
  final String name;
  final String symbol;

  String get searchableText => '$code $name $symbol'.toLowerCase();
}

const onboardingCurrencies = <CurrencyOption>[
  CurrencyOption(code: 'AED', name: 'UAE Dirham', symbol: 'د.إ'),
  CurrencyOption(code: 'AUD', name: 'Australian Dollar', symbol: r'A$'),
  CurrencyOption(code: 'BRL', name: 'Brazilian Real', symbol: r'R$'),
  CurrencyOption(code: 'CAD', name: 'Canadian Dollar', symbol: r'CA$'),
  CurrencyOption(code: 'CHF', name: 'Swiss Franc', symbol: 'CHF'),
  CurrencyOption(code: 'CNY', name: 'Chinese Yuan', symbol: '¥'),
  CurrencyOption(code: 'DKK', name: 'Danish Krone', symbol: 'kr'),
  CurrencyOption(code: 'EUR', name: 'Euro', symbol: '€'),
  CurrencyOption(code: 'GBP', name: 'British Pound', symbol: '£'),
  CurrencyOption(code: 'INR', name: 'Indian Rupee', symbol: '₹'),
  CurrencyOption(code: 'JPY', name: 'Japanese Yen', symbol: '¥'),
  CurrencyOption(code: 'MAD', name: 'Moroccan Dirham', symbol: 'MAD'),
  CurrencyOption(code: 'MXN', name: 'Mexican Peso', symbol: r'MX$'),
  CurrencyOption(code: 'NOK', name: 'Norwegian Krone', symbol: 'kr'),
  CurrencyOption(code: 'NZD', name: 'New Zealand Dollar', symbol: r'NZ$'),
  CurrencyOption(code: 'PLN', name: 'Polish Zloty', symbol: 'zł'),
  CurrencyOption(code: 'SEK', name: 'Swedish Krona', symbol: 'kr'),
  CurrencyOption(code: 'SGD', name: 'Singapore Dollar', symbol: r'S$'),
  CurrencyOption(code: 'USD', name: 'US Dollar', symbol: r'$'),
  CurrencyOption(code: 'ZAR', name: 'South African Rand', symbol: 'R'),
];

class CountryOption {
  const CountryOption({
    required this.name,
    required this.code,
    required this.currencyCode,
  });

  final String name;
  final String code;
  final String currencyCode;

  String get searchableText => '$name $code'.toLowerCase();
}

const onboardingCountries = <CountryOption>[
  CountryOption(name: 'Australia', code: 'AU', currencyCode: 'AUD'),
  CountryOption(name: 'Austria', code: 'AT', currencyCode: 'EUR'),
  CountryOption(name: 'Belgium', code: 'BE', currencyCode: 'EUR'),
  CountryOption(name: 'Brazil', code: 'BR', currencyCode: 'BRL'),
  CountryOption(name: 'Canada', code: 'CA', currencyCode: 'CAD'),
  CountryOption(name: 'Denmark', code: 'DK', currencyCode: 'DKK'),
  CountryOption(name: 'France', code: 'FR', currencyCode: 'EUR'),
  CountryOption(name: 'Germany', code: 'DE', currencyCode: 'EUR'),
  CountryOption(name: 'India', code: 'IN', currencyCode: 'INR'),
  CountryOption(name: 'Ireland', code: 'IE', currencyCode: 'EUR'),
  CountryOption(name: 'Italy', code: 'IT', currencyCode: 'EUR'),
  CountryOption(name: 'Japan', code: 'JP', currencyCode: 'JPY'),
  CountryOption(name: 'Morocco', code: 'MA', currencyCode: 'MAD'),
  CountryOption(name: 'Netherlands', code: 'NL', currencyCode: 'EUR'),
  CountryOption(name: 'New Zealand', code: 'NZ', currencyCode: 'NZD'),
  CountryOption(name: 'Norway', code: 'NO', currencyCode: 'NOK'),
  CountryOption(name: 'Poland', code: 'PL', currencyCode: 'PLN'),
  CountryOption(name: 'Portugal', code: 'PT', currencyCode: 'EUR'),
  CountryOption(name: 'South Africa', code: 'ZA', currencyCode: 'ZAR'),
  CountryOption(name: 'Spain', code: 'ES', currencyCode: 'EUR'),
  CountryOption(name: 'Sweden', code: 'SE', currencyCode: 'SEK'),
  CountryOption(name: 'Switzerland', code: 'CH', currencyCode: 'CHF'),
  CountryOption(name: 'United Kingdom', code: 'GB', currencyCode: 'GBP'),
  CountryOption(name: 'United States', code: 'US', currencyCode: 'USD'),
  CountryOption(
    name: 'Other / international',
    code: 'OTHER',
    currencyCode: 'USD',
  ),
];

class TaxIdOption {
  const TaxIdOption({
    required this.label,
    required this.description,
    this.countryCodes = const <String>[],
  });

  final String label;
  final String description;
  final List<String> countryCodes;

  String get searchableText => '$label $description'.toLowerCase();
}

const onboardingTaxIds = <TaxIdOption>[
  TaxIdOption(
    label: 'EIN',
    description: 'Employer Identification Number',
    countryCodes: ['US'],
  ),
  TaxIdOption(
    label: 'VAT ID',
    description: 'Value Added Tax identification number',
    countryCodes: [
      'AT',
      'BE',
      'DE',
      'ES',
      'FR',
      'GB',
      'IE',
      'IT',
      'MA',
      'NL',
      'PL',
      'PT',
    ],
  ),
  TaxIdOption(
    label: 'VAT',
    description: 'Value Added Tax number (general label)',
    countryCodes: [
      'AT',
      'BE',
      'DE',
      'ES',
      'FR',
      'GB',
      'IE',
      'IT',
      'MA',
      'NL',
      'PL',
      'PT',
    ],
  ),
  TaxIdOption(
    label: 'ICE',
    description: 'Identifiant Commun de l’Entreprise',
    countryCodes: ['MA'],
  ),
  TaxIdOption(
    label: 'SIRET',
    description: 'French business establishment number',
    countryCodes: ['FR'],
  ),
  TaxIdOption(
    label: 'NIF',
    description: 'National tax identification number',
    countryCodes: ['ES', 'PT', 'BR'],
  ),
  TaxIdOption(
    label: 'ABN',
    description: 'Australian Business Number',
    countryCodes: ['AU'],
  ),
  TaxIdOption(
    label: 'GST',
    description: 'Goods and Services Tax number',
    countryCodes: ['AU', 'CA', 'IN', 'NZ', 'SG', 'ZA'],
  ),
  TaxIdOption(
    label: 'TIN',
    description: 'Taxpayer Identification Number',
    countryCodes: ['IN', 'US', 'OTHER'],
  ),
  TaxIdOption(
    label: 'SSN',
    description: 'Social Security Number',
    countryCodes: ['US'],
  ),
  TaxIdOption(
    label: 'Tax ID',
    description: 'General tax identification number',
  ),
  TaxIdOption(
    label: 'Other',
    description: 'Another local or international tax ID type',
  ),
];

class PaymentMethodOption {
  const PaymentMethodOption({
    required this.label,
    required this.icon,
    required this.hint,
    this.requiresDetails = true,
  });

  final String label;
  final String icon;
  final String hint;
  final bool requiresDetails;
}

const onboardingPaymentMethods = <PaymentMethodOption>[
  PaymentMethodOption(
    label: 'Bank transfer',
    icon: '🏦',
    hint: 'Bank name, account holder, and account details',
  ),
  PaymentMethodOption(
    label: 'IBAN',
    icon: '🌍',
    hint: 'Your IBAN or international bank account number',
  ),
  PaymentMethodOption(
    label: 'Routing number',
    icon: '🏛️',
    hint: 'Routing and account number',
  ),
  PaymentMethodOption(
    label: 'PayPal',
    icon: '◉',
    hint: 'PayPal email or payment link',
  ),
  PaymentMethodOption(
    label: 'Stripe',
    icon: 'S',
    hint: 'Stripe payment link or account email',
  ),
  PaymentMethodOption(
    label: 'Cash',
    icon: '💵',
    hint: 'Cash payment',
    requiresDetails: false,
  ),
  PaymentMethodOption(
    label: 'Other',
    icon: '＋',
    hint: 'Describe another way clients can pay',
  ),
];

CountryOption? countryForCode(String? code) {
  if (code == null) return null;
  for (final country in onboardingCountries) {
    if (country.code == code) return country;
  }
  return null;
}

CurrencyOption currencyForCode(String code) {
  for (final currency in onboardingCurrencies) {
    if (currency.code == code) return currency;
  }
  return onboardingCurrencies.firstWhere((currency) => currency.code == 'USD');
}

List<TaxIdOption> suggestedTaxIds(String? countryCode) {
  if (countryCode == null) return onboardingTaxIds.take(4).toList();
  final suggested = onboardingTaxIds
      .where((option) => option.countryCodes.contains(countryCode))
      .toList();
  return suggested.isEmpty ? onboardingTaxIds.take(4).toList() : suggested;
}
