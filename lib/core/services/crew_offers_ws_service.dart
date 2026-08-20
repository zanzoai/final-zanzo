// lib/core/services/crew_offers_ws_service.dart
// WS /api/v1/ws/crew/me?token=<jwt>
// Receive-only: offer.received / offer.expired / task.cancelled
// Accept/reject still go through REST (ZanCrewApi / ApiService).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_service.dart';

class CrewOffersWsService with ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  bool _connected = false;
  bool get isConnected => _connected;

  // Set these before calling connect().
  void Function(String taskId)? onOfferReceived;
  void Function(String taskId)? onOfferExpired;
  void Function(String taskId)? onTaskCancelled;
  /// Admin force-offline (or re-online): `crew.status_changed` carries the new
  /// online state. See ZANZO_FLUTTER_API_REFERENCE.md §5.1.
  void Function(bool isOnline)? onStatusChanged;

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
      if (kDebugMode) print('[CrewOffersWS] no token — skipping connect');
      return;
    }

    final wsUri = Uri.parse(ApiService.wsBaseUrl('/api/v1/ws/crew/me'))
        .replace(queryParameters: {'token': token});

    if (kDebugMode) print('[CrewOffersWS] connecting → $wsUri');

    try {
      _channel = WebSocketChannel.connect(wsUri);
    } catch (e) {
      if (kDebugMode) print('[CrewOffersWS] connect error: $e');
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
        if (kDebugMode) print('[CrewOffersWS] stream error: $e');
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
          _notify();
          if (kDebugMode) print('[CrewOffersWS] ✅ connected');
          break;
        case 'offer.received':
          final taskId = data['task_id']?.toString() ?? '';
          if (kDebugMode) print('[CrewOffersWS] offer.received task=$taskId');
          onOfferReceived?.call(taskId);
          break;
        case 'offer.expired':
          onOfferExpired?.call(data['task_id']?.toString() ?? '');
          break;
        case 'task.cancelled':
          onTaskCancelled?.call(data['task_id']?.toString() ?? '');
          break;
        case 'crew.status_changed':
          // Admin forced the crew offline (today only is_online:false is sent).
          final isOnline = data['is_online'] == true;
          if (kDebugMode) {
            print('[CrewOffersWS] crew.status_changed is_online=$isOnline');
          }
          onStatusChanged?.call(isOnline);
          break;
        case 'error':
          final code = data['code'] as int? ?? 0;
          if (kDebugMode) {
            print('[CrewOffersWS] server error $code: ${data['message']}');
          }
          // 4001 = bad/expired token → refresh then reconnect
          if (code == 4001) _handleTokenExpired();
          break;
      }
    } catch (e) {
      if (kDebugMode) print('[CrewOffersWS] frame parse error: $e');
    }
  }

  void _onClosed() {
    if (kDebugMode) print('[CrewOffersWS] closed');
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
      print('[CrewOffersWS] reconnect in ${delay.inSeconds}s '
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
