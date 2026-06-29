// lib/core/services/task_chat_ws_service.dart
// WS /api/v1/ws/tasks/{task_id}/messages?token=<jwt>
// The connected frame ships the full message history — no separate REST fetch needed.
// message.new pushes incoming messages; sending still uses REST POST /messages/send.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_service.dart';
import 'messages_api.dart';

class TaskChatWsService with ChangeNotifier {
  final String taskId;

  TaskChatWsService(this.taskId);

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  bool _connected = false;
  bool get isConnected => _connected;

  List<ChatMessage> _messages = [];

  // Returns an unmodifiable view; the screen rebuilds via notifyListeners.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

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
      if (kDebugMode) print('[TaskChatWS] no token — skipping connect');
      return;
    }

    final wsUri =
        Uri.parse(ApiService.wsBaseUrl('/api/v1/ws/tasks/$taskId/messages'))
            .replace(queryParameters: {'token': token});

    if (kDebugMode) print('[TaskChatWS] connecting → $wsUri');

    try {
      _channel = WebSocketChannel.connect(wsUri);
    } catch (e) {
      if (kDebugMode) print('[TaskChatWS] connect error: $e');
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
        if (kDebugMode) print('[TaskChatWS] stream error: $e');
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
          // Full message history delivered in the connected frame.
          final rawList = data['messages'];
          if (rawList is List) {
            _messages = rawList
                .map((e) =>
                    ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          }
          _notify();
          if (kDebugMode) {
            print('[TaskChatWS] ✅ connected msgs=${_messages.length}');
          }
          break;

        case 'message.new':
          // data is the MessageRead object directly.
          final msg = ChatMessage.fromJson(data);
          if (!_messages.any((m) => m.id == msg.id)) {
            _messages
              ..add(msg)
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          }
          _notify();
          break;

        case 'error':
          final code = data['code'] as int? ?? 0;
          if (kDebugMode) {
            print('[TaskChatWS] server error $code: ${data['message']}');
          }
          if (code == 4001) _handleTokenExpired();
          break;
      }
    } catch (e) {
      if (kDebugMode) print('[TaskChatWS] frame parse error: $e');
    }
  }

  void _onClosed() {
    if (kDebugMode) print('[TaskChatWS] closed');
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
      print('[TaskChatWS] reconnect in ${delay.inSeconds}s '
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
