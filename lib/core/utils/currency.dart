
// Simple utility that formats numbers into INR or GBP currency strings

// lib/core/utils/currency.dart

import 'package:intl/intl.dart';

class CurrencyFormatter {
  static String format(num amount, String currencyCode) {
    final format = NumberFormat.currency(
      locale: currencyCode == 'INR' ? 'en_IN' : 'en_GB',
      symbol: currencyCode == 'INR' ? '₹' : '£',
    );
    return format.format(amount);
  }
}