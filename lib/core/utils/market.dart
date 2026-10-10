// lib/core/utils/market.dart
//
// The signed-in user's market: the UK (default, main market) or India.
// It comes from the server — the `country_code` / `region` saved after sign-in
// and location sync — and decides local display conventions such as miles in
// the UK and kilometres in India. Prices always use the currency the server
// sends (see CurrencyFormatter), not this.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/services/token_store.dart';

class Market {
  Market._();

  static bool _india = false;

  /// True for India, false for the UK (and whenever the market is unknown).
  static bool get isIndia => _india;

  /// Reads the saved market. Call once at start-up; [update] keeps it fresh.
  /// Falls back to the `country_code` / `region` claims in the login token for
  /// sessions that signed in before the app started saving them.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var country = prefs.getString('country_code');
      var region = prefs.getString('region');
      if ((country ?? '').isEmpty && (region ?? '').isEmpty) {
        final claims = _claims(await TokenStore.accessToken());
        country = claims['country_code']?.toString();
        region = claims['region']?.toString();
      }
      update(countryCode: country, region: region);
    } catch (_) {
      _india = false;
    }
  }

  // Reads (does not verify) the payload of a JWT — only used for display.
  static Map<String, dynamic> _claims(String? jwt) {
    final parts = (jwt ?? '').split('.');
    if (parts.length != 3) return const {};
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Called whenever the server sends a new country / region.
  static void update({String? countryCode, String? region}) {
    final cc = (countryCode ?? '').toUpperCase();
    final r = (region ?? '').toUpperCase();
    _india = cc.isNotEmpty ? cc == 'IN' : r == 'IN';
  }

  static const double _kmPerMile = 1.609344;

  /// A distance given in km: "350 m" / "2.4 km" in India, "0.2 mi" / "1.5 mi"
  /// in the UK.
  static String distance(num km) {
    if (_india) {
      if (km < 1) return '${(km * 1000).round()} m';
      return '${km.toStringAsFixed(1)} km';
    }
    final mi = km / _kmPerMile;
    return '${mi < 10 ? mi.toStringAsFixed(1) : mi.round()} mi';
  }

  /// A travel radius given in km: "5 km" in India, "3 mi" in the UK.
  /// [precise] keeps one decimal in miles, so a km slider never shows the
  /// same label for two neighbouring steps.
  static String radius(num km, {bool precise = false}) {
    if (_india) return '${km.round()} km';
    final mi = km / _kmPerMile;
    return (precise || mi < 1)
        ? '${mi.toStringAsFixed(1)} mi'
        : '${mi.round()} mi';
  }
}
