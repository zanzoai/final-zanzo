// lib/core/constants/service_zones.dart

class ServiceZone {
  final String name;
  final double lat;
  final double lng;
  final double radiusKm;

  const ServiceZone({
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusKm,
  });
}

const serviceZones = [
  // 🇮🇳 India
  ServiceZone(name: "Vijayawada", lat: 16.5062, lng: 80.6480, radiusKm: 50.0),
  ServiceZone(name: "Hyderabad", lat: 17.3850, lng: 78.4867, radiusKm: 50.0),

  // 🇬🇧 UK
  ServiceZone(name: "Uxbridge", lat: 51.5466, lng: -0.4773, radiusKm: 30.0),
];
