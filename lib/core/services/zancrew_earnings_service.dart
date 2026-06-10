import 'package:zanzo_frontend/core/services/api_service.dart';

class ZanCrewEarningsService {
  static Future<Map<String, dynamic>> getEarnings(String crewUserId) async {
    return ApiService.getCrewEarnings();
  }
}
