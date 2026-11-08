// lib/core/utils/currency.dart
//
// The one place that turns an amount + currency code into display text.
// Zanzo runs in two markets: the UK (GBP, the default) and India (INR).
// Always show the currency the server sent for that task / quote / earning —
// never assume one.

import 'package:intl/intl.dart';
import 'package:zanzo_frontend/core/utils/market.dart';

class CurrencyFormatter {
  CurrencyFormatter._();

  static String _code(String? currencyCode) =>
      (currencyCode ?? '').toUpperCase() == 'INR' ? 'INR' : 'GBP';

  /// '₹' for INR, '£' for everything else.
  static String symbol(String? currencyCode) =>
      _code(currencyCode) == 'INR' ? '₹' : '£';

  /// £1,234.50 / ₹1,23,450.00 (Indian digit grouping for rupees).
  /// With [compact], whole amounts drop the decimals (£12, ₹150).
  static String format(
    num amount,
    String? currencyCode, {
    bool compact = false,
  }) {
    final code = _code(currencyCode);
    final whole = amount == amount.truncate();
    return NumberFormat.currency(
      locale: code == 'INR' ? 'en_IN' : 'en_GB',
      symbol: symbol(code),
      decimalDigits: compact && whole ? 0 : 2,
    ).format(amount);
  }

  /// Formats an amount in minor units (pence / paise).
  static String formatMinor(
    num minorUnits,
    String? currencyCode, {
    bool compact = false,
  }) => format(minorUnits / 100.0, currencyCode, compact: compact);

  /// Best guess of the signed-in user's currency, for placeholders shown
  /// before the server answers: India → INR, everything else → GBP.
  static String userCurrency() => Market.isIndia ? 'INR' : 'GBP';
}
