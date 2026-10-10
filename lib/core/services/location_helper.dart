// This file handles GPS permission + fetching coordinates + converting coordinates into an address.


// lib/core/services/location_helper.dart

import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'api_service.dart';

class LocationHelper {
  // ---------------------------------------------------------------------------
  // 1) GET CURRENT GPS LOCATION
  // ---------------------------------------------------------------------------

  static Future<Position> getCurrentLocation() async {
    // Check if device location is enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        "❌ Location services are disabled. Please enable them in settings.",
      );
    }

    // Check & request permissions
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        throw Exception("❌ Location permission denied by user.");
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        "❌ Location permissions are permanently denied. Enable them from app settings.",
      );
    }

    // Accurate GPS position — but never wait forever: indoors or with a weak
    // signal a fix may never arrive, which left callers (e.g. the sign-in
    // dialog) spinning indefinitely. Fall back to the last known position.
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) rethrow;
      position = last;
    }

    // Notify backend to reverse-geocode and embed country_code in JWT.
    // Only runs if authenticated; errors are swallowed so they never block callers.
    await ApiService.setUserLocation(
      lat: position.latitude,
      lng: position.longitude,
    ).catchError((_) => null);

    return position;
  }

  // ---------------------------------------------------------------------------
  // 2) REVERSE GEOCODING → LAT/LNG → READABLE ADDRESS
  // ---------------------------------------------------------------------------

  static Future<String> getReadableAddressFromLatLng(
    Position position,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return "${place.name}, ${place.street}, ${place.locality}";
      }

      return "❓ Location details not available";
    } catch (e) {
      return "⚠️ Failed to get address: $e";
    }
  }
}