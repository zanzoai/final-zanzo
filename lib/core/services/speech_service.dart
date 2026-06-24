// lib/core/services/speech_service.dart
//
// On-device speech-to-text using the speech_to_text package.
// Drop-in replacement for VoiceWsService (same public API surface).
// Uses iOS SFSpeechRecognizer / Android SpeechRecognizer — no backend needed.

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService with ChangeNotifier {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  // ── State ──────────────────────────────────────────────────────────────────

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  // speech_to_text has no separate transcribing phase; kept for API compat.
  bool get isTranscribing => false;

  // Live partial words shown while the mic is open.
  String _partialText = '';
  String get partialText => _partialText;

  // Committed result, set when the engine returns a final result or on stop().
  String _finalText = '';
  String get finalText => _finalText;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Initialise / request permissions. Returns false if unavailable or denied.
  Future<bool> initialize() async {
    _initialized = await _speech.initialize(
      onError: _onError,
      onStatus: _onStatus,
    );
    return _initialized;
  }

  /// Start listening. Returns false if permission is denied or unavailable.
  Future<bool> start() async {
    if (_isRecording) return true;

    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return false;
    }

    _partialText = '';
    _finalText = '';
    _isRecording = true;
    notifyListeners();

    _speech.listen(
      onResult: _onResult,
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
      ),
    );

    return true;
  }

  /// Stop listening. Any partial text is promoted to finalText.
  Future<void> stop() async {
    if (!_isRecording) return;
    await _speech.stop();
    // _onStatus('done') / _onResult(final) will fire and update state.
    // Guard: if neither fires (very short recordings), clear recording flag.
    if (_isRecording) {
      if (_partialText.isNotEmpty) {
        _finalText = _partialText;
        _partialText = '';
      }
      _isRecording = false;
      notifyListeners();
    }
  }

  /// Clear partial and final text (called by HomeScreen after inserting text).
  void clearText() {
    _partialText = '';
    _finalText = '';
    notifyListeners();
  }

  /// Clean up (called from dispose).
  Future<void> disposeAll() async {
    _speech.cancel();
    _isRecording = false;
    _initialized = false;
  }

  // ── Internal callbacks ─────────────────────────────────────────────────────

  void _onResult(SpeechRecognitionResult result) {
    if (result.finalResult) {
      _finalText = result.recognizedWords;
      _partialText = '';
      _isRecording = false;
    } else {
      _partialText = result.recognizedWords;
    }
    notifyListeners();
  }

  void _onStatus(String status) {
    if (kDebugMode) debugPrint('[Speech] status: $status');
    // 'done' / 'notListening' → engine stopped (silence timeout or stop())
    if ((status == 'done' || status == 'notListening') && _isRecording) {
      // Promote any pending partial to final so HomeScreen can insert it.
      if (_partialText.isNotEmpty) {
        _finalText = _partialText;
        _partialText = '';
      }
      _isRecording = false;
      notifyListeners();
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (kDebugMode) debugPrint('[Speech] error: ${error.errorMsg}');
    _isRecording = false;
    _partialText = '';
    notifyListeners();
  }
}
