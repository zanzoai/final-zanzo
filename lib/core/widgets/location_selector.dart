// Autocomplete + place picker with service-area validation.
// Search bar that uses Google Places to pick a location and confirm it’s inside your service zone

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/constants/service_zones.dart';

const googleMapsKey = "AIzaSyDjDx3TOFqJtSls96YrM2m86t3KFwIE4b0";

class LocationSelector extends StatefulWidget {
  final TextEditingController controller;
  final Function(String address, double lat, double lng)? onSelected;
  final IconData? icon;
  final Color? iconColor;

  const LocationSelector({
    super.key,
    required this.controller,
    this.onSelected,
    this.icon,
    this.iconColor,
  });

  @override
  State<LocationSelector> createState() => _LocationSelectorState();
}

class _LocationSelectorState extends State<LocationSelector> {
  List<dynamic> predictions = [];

  double _degToRad(double d) => d * (pi / 180);

  double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  bool isInsideServiceArea(double lat, double lng) {
    for (final zone in serviceZones) {
      if (distanceKm(lat, lng, zone.lat, zone.lng) <= zone.radiusKm) {
        return true;
      }
    }
    return false;
  }

  // -----------------------------
  // AUTOCOMPLETE SEARCH
  // -----------------------------
  Future<void> autoCompleteSearch(String value) async {
    if (value.isEmpty) {
      setState(() => predictions = []);
      return;
    }

    final url =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json"
        "?input=$value&key=$googleMapsKey";

    final res = await http.get(Uri.parse(url));
    final data = jsonDecode(res.body);

    if (!mounted) return;
    setState(() => predictions = data["predictions"] ?? []);
  }

  // -----------------------------
  // SELECT GOOGLE PREDICTION
  // -----------------------------
  Future<void> selectPrediction(Map p) async {
    final placeId = p["place_id"];
    if (placeId == null) return;

    final url =
        "https://maps.googleapis.com/maps/api/place/details/json"
        "?place_id=$placeId&key=$googleMapsKey";

    final res = await http.get(Uri.parse(url));
    final result = jsonDecode(res.body)["result"];
    if (result == null) return;

    final loc = result["geometry"]?["location"];
    if (loc == null) return;

    final lat = (loc["lat"] as num).toDouble();
    final lng = (loc["lng"] as num).toDouble();

    // 🚫 Outside service area
    if (!isInsideServiceArea(lat, lng)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("We’re not serving this location yet. Coming soon!"),
        ),
      );
      return;
    }

    final address = result["formatted_address"] ?? "";

    // ✅ VALID SELECTION
    widget.controller.text = address;
    predictions = [];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("review_address", address);
    await prefs.setDouble("review_lat", lat);
    await prefs.setDouble("review_lng", lng);
    await prefs.setString("review_place_id", placeId);

    widget.onSelected?.call(address, lat, lng);

    if (mounted) setState(() {});
  }

  // -----------------------------
  // INVALIDATE LOCATION
  // -----------------------------
  Future<void> _invalidateLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("review_address");
    await prefs.remove("review_lat");
    await prefs.remove("review_lng");
    await prefs.remove("review_place_id");
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: widget.controller,

          // 🔥 KEY FIX: typing invalidates previous selection
          onChanged: (value) async {
            await _invalidateLocation();
            autoCompleteSearch(value);
          },

          decoration: InputDecoration(
            hintText: "Search location",

            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(
                widget.icon ?? Icons.location_on_rounded,
                color: widget.iconColor ?? const Color(0xFFFF7A00),
                size: 22,
              ),
            ),

            suffixIcon: widget.controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      widget.controller.clear();
                      await _invalidateLocation();
                      setState(() => predictions = []);
                    },
                  )
                : null,

            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        if (predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: predictions.length,
              itemBuilder: (context, i) {
                final p = predictions[i];
                return ListTile(
                  leading: const Icon(
                    Icons.location_on_rounded,
                    color: Color(0xFFFF7A00),
                  ),
                  title: Text(p["description"] ?? ""),
                  onTap: () => selectPrediction(p),
                );
              },
            ),
          ),
      ],
    );
  }
}
