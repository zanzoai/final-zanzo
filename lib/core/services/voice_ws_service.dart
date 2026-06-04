// lib/core/services/voice_ws_service.dart
// Streams mic audio to backend via WebSocket and receives final speech-to-text results 
//Streams PCM16 audio to backend WebSocket → receives transcripts.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';

class VoiceWsService with ChangeNotifier {
  static const int sampleRate = 16000;
  static const Codec codec = Codec.pcm16;

  FlutterSoundRecorder? _recorder;
  bool _recorderOpened = false;

  StreamController<Uint8List>? _pcmController;
  StreamSubscription<Uint8List>? _pcmSub;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _pingTimer;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool _isTranscribing = false;
  bool get isTranscribing => _isTranscribing;

  String _partial = "";
  String _finalText = "";
  String get partialText => _partial;
  String get finalText => _finalText;

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    if (_isRecording) return;

    await _ensureRecorderReady();
    await _ensureWsReady();

    _partial = "";
    _finalText = "";
    _isTranscribing = false;
    notifyListeners();

    await _disposePcmStream();
    _pcmController = StreamController<Uint8List>.broadcast();

    _pcmSub = _pcmController!.stream.listen(
      (bytes) {
        try {
          _channel?.sink.add(bytes);
        } catch (_) {}
      },
      onError: (e) {
        if (kDebugMode) print("PCM error: $e");
      },
    );

    _isRecording = true;
    notifyListeners();

    await _recorder!.startRecorder(
      codec: codec,
      sampleRate: sampleRate,
      numChannels: 1,
      bitRate: 16000,
      toStream: _pcmController!.sink,
    );
  }

  Future<void> stop() async {
    if (!_isRecording) return;

    _isRecording = false;
    _isTranscribing = true;
    notifyListeners();

    try {
      await _recorder?.stopRecorder();
    } catch (_) {}

    await _disposePcmStream();

    try {
      _channel?.sink.add('{"cmd":"flush"}');
    } catch (_) {}

    const total = Duration(milliseconds: 2000);
    const step = Duration(milliseconds: 60);
    var waited = Duration.zero;

    while (_isTranscribing && waited < total) {
      await Future.delayed(step);
      waited += step;
    }

    if (_isTranscribing) {
      _isTranscribing = false;
      notifyListeners();
    }
  }

  Future<void> disposeAll() async {
    try {
      if (_isRecording) await stop();
    } catch (_) {}

    await _closeWs();
    await _closeRecorder();
  }

  void clearText() {
    _partial = "";
    _finalText = "";
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // INTERNALS
  // ---------------------------------------------------------------------------

  Future<void> _ensureRecorderReady() async {
    if (_recorder != null && _recorderOpened) return;

    _recorder ??= FlutterSoundRecorder();
    if (!_recorderOpened) {
      await _recorder!.openRecorder();
      _recorderOpened = true;
    }
    await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 40));
  }

  Future<void> _ensureWsReady() async {
    if (_channel != null) return;

    final wsUrl = ApiService.wsBaseUrl("/voice/live");
    if (kDebugMode) print("Connecting voice WS → $wsUrl");

    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) {
        try {
          _channel?.sink.add('{"type":"ping"}');
        } catch (_) {}
      },
    );

    _wsSub = _channel!.stream.listen(
      (data) {
        try {
          if (data is String) {
            final obj = jsonDecode(data);
            if (obj is Map && obj.containsKey("text")) {
              final text = "${obj["text"] ?? ""}".trim();
              final isFinal = obj["final"] == true;

              if (isFinal) {
                if (text.isNotEmpty) {
                  _finalText = _finalText.isEmpty
                      ? text
                      : ("$_finalText $text").trim();
                }
                _partial = "";
                _isTranscribing = false;
              } else {
                _partial = text;
              }
              notifyListeners();
            }
          }
        } catch (e) {
          if (kDebugMode) print("WS decode error: $e");
        }
      },
      onDone: () {
        if (kDebugMode) print("WS closed");
        _cleanupWs();
      },
      onError: (err) {
        if (kDebugMode) print("WS error: $err");
        _cleanupWs();
      },
      cancelOnError: true,
    );

    if (kDebugMode) print("WS connected");
  }

  Future<void> _disposePcmStream() async {
    try {
      await _pcmSub?.cancel();
    } catch (_) {}
    _pcmSub = null;

    try {
      await _pcmController?.close();
    } catch (_) {}
    _pcmController = null;
  }

  Future<void> _closeRecorder() async {
    try {
      if (_recorderOpened) {
        await _recorder?.closeRecorder();
        _recorderOpened = false;
      }
    } catch (_) {}
    _recorder = null;
  }

  Future<void> _closeWs() async {
    _pingTimer?.cancel();
    _pingTimer = null;

    try {
      await _wsSub?.cancel();
    } catch (_) {}
    _wsSub = null;

    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;
  }

  void _cleanupWs() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _wsSub = null;
    _channel = null;
  }
}