// lib/core/services/task_events_ws_service.dart
// WS /api/v1/ws/tasks/{task_id}?token=<jwt>
// Live task status + crew location for the task owner (TrackJobScreen).
// task.status_changed / crew.location

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_service.dart';

class TaskEventsWsService with ChangeNotifier {
  final String taskId;

  TaskEventsWsService(this.taskId);

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  bool _connected = false;
  bool get isConnected => _connected;

  // Latest task status received over the socket.
  String? _status;
  String? get status => _status;

  // Latest crew location received over the socket.
  double? _crewLat;
  double? _crewLng;
  double? get crewLat => _crewLat;
  double? get crewLng => _crewLng;

  // Optional callbacks — wired up by the screen after construction.
  void Function(String status, String? note)? onStatusChanged;
  void Function(double lat, double lng)? onCrewLocation;

  int _reconnectAttempts = 0;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  Future<void> connect() async {
    if (_channel != null) return;
    _disposed = false;
    await _doConnect();
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    await _closeWs();
  }

  // ---------------------------------------------------------------------------
  // INTERNALS
  // ---------------------------------------------------------------------------

  Future<void> _doConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';
    if (token.isEmpty) {
      if (kDebugMode) print('[TaskEventsWS] no token — skipping connect');
      return;
    }

    final wsUri =
        Uri.parse(ApiService.wsBaseUrl('/api/v1/ws/tasks/$taskId'))
            .replace(queryParameters: {'token': token});

    if (kDebugMode) print('[TaskEventsWS] connecting → $wsUri');

    try {
      _channel = WebSocketChannel.connect(wsUri);
    } catch (e) {
      if (kDebugMode) print('[TaskEventsWS] connect error: $e');
      _scheduleReconnect();
      return;
    }

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        _channel?.sink.add('{"type":"ping"}');
      } catch (_) {}
    });

    _sub = _channel!.stream.listen(
      _onFrame,
      onDone: _onClosed,
      onError: (e) {
        if (kDebugMode) print('[TaskEventsWS] stream error: $e');
        _cleanupWs();
        _scheduleReconnect();
      },
      cancelOnError: true,
    );
  }

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    try {
      final obj = jsonDecode(raw) as Map<String, dynamic>;
      final event = obj['event']?.toString() ?? '';
      final data = (obj['data'] is Map)
          ? Map<String, dynamic>.from(obj['data'] as Map)
          : <String, dynamic>{};

      switch (event) {
        case 'connected':
          _connected = true;
          _reconnectAttempts = 0;
          _status = data['status']?.toString();
          _notify();
          if (kDebugMode) print('[TaskEventsWS] ✅ connected status=$_status');
          break;
        case 'task.status_changed':
          _status = data['status']?.toString();
          final note = data['note']?.toString();
          _notify();
          onStatusChanged?.call(_status ?? '', note);
          if (kDebugMode) print('[TaskEventsWS] status→$_status note=$note');
          break;
        case 'crew.location':
          final lat = (data['lat'] as num?)?.toDouble();
          final lng = (data['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            _crewLat = lat;
            _crewLng = lng;
            _notify();
            onCrewLocation?.call(lat, lng);
          }
          break;
        case 'error':
          final code = data['code'] as int? ?? 0;
          if (kDebugMode) {
            print('[TaskEventsWS] server error $code: ${data['message']}');
          }
          if (code == 4001) _handleTokenExpired();
          break;
      }
    } catch (e) {
      if (kDebugMode) print('[TaskEventsWS] frame parse error: $e');
    }
  }

  void _onClosed() {
    if (kDebugMode) print('[TaskEventsWS] closed');
    _cleanupWs();
    if (!_disposed) _scheduleReconnect();
  }

  Future<void> _handleTokenExpired() async {
    await ApiService.refreshToken();
    _reconnectAttempts = 0;
    await _closeWs();
    if (!_disposed) await _doConnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    final delay = _backoff(_reconnectAttempts);
    _reconnectAttempts++;
    if (kDebugMode) {
      print('[TaskEventsWS] reconnect in ${delay.inSeconds}s '
          '(attempt $_reconnectAttempts)');
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (!_disposed) await _doConnect();
    });
  }

  static Duration _backoff(int attempt) {
    final s = (1 << attempt.clamp(0, 5)).clamp(1, 30);
    return Duration(seconds: s);
  }

  void _cleanupWs() {
    _connected = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub = null;
    _channel = null;
    _notify();
  }

  Future<void> _closeWs() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;
    _connected = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    try {
      _sub?.cancel();
    } catch (_) {}
    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    super.dispose();
  }
}
