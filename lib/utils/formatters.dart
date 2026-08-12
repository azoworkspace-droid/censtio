import 'package:intl/intl.dart';

// Shared formatting utilities for the Freelancer app.

/// Formats monetary amounts with locale-aware grouping and decimal separators.
/// The symbol remains user-controlled so custom and local currency symbols are
/// preserved. Pass [currencyCode] when it is available for more accurate
/// regional formatting.
String formatCurrency(
  double amount,
  String currencySymbol, {
  String? currencyCode,
  String? locale,
}) {
  final format = NumberFormat.currency(
    locale: locale ?? _localeForCurrency(currencyCode, currencySymbol),
    symbol: currencySymbol,
    decimalDigits: 2,
  );
  return format.format(amount);
}

String _localeForCurrency(String? currencyCode, String symbol) {
  switch (currencyCode?.toUpperCase()) {
    case 'EUR':
      return 'de_DE';
    case 'GBP':
      return 'en_GB';
    case 'CHF':
      return 'de_CH';
    case 'MAD':
      return 'fr_MA';
    case 'CAD':
      return 'en_CA';
    case 'AUD':
      return 'en_AU';
    case 'INR':
      return 'en_IN';
    case 'JPY':
      return 'ja_JP';
    case 'BRL':
      return 'pt_BR';
    case 'SEK':
      return 'sv_SE';
    case 'NOK':
      return 'nb_NO';
    case 'DKK':
      return 'da_DK';
    case 'PLN':
      return 'pl_PL';
    case 'USD':
      return 'en_US';
  }
  // A symbol alone can be custom or ambiguous (for example, "kr"), so use
  // the stable English fallback until the user selects an ISO code.
  return 'en_US';
}

/// Formats a DateTime into a readable string (e.g. "Aug 3, 2026").
String formatDate(DateTime date) {
  final months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
