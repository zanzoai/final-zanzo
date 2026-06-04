// This file handles GPS permission + fetching coordinates + converting coordinates into an address.


// lib/core/services/location_helper.dart

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

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

    // Return accurate GPS position
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
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