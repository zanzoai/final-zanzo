// lib/core/services/speech_service.dart
//
// On-device speech-to-text with automatic long-dictation support (up to 3 min).
// Native STT sessions cap at ~60 s; this service restarts them transparently,
// accumulating text across restarts so the caller sees a single continuous session.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService with ChangeNotifier {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  // ── Long-dictation constants ───────────────────────────────────────────────

  static const int _totalMaxSecs = 180; // hard 3-minute cap
  static const int _sessionSecs = 55;   // listenFor per native session
  static const int _pauseSecs = 15;     // silence before native session ends
  static const int _restartDelayMs = 400; // gap between sessions

  // ── Long-dictation state ───────────────────────────────────────────────────

  bool _isLongDictation = false;  // true from tap-start until full stop
  bool _userStopped = false;      // set when user manually taps stop
  bool _endedByStop = false;      // guard: prevents _onResult double-committing
  String _accumulatedText = '';   // confirmed words from previous auto-restarts
  DateTime? _dictationStart;      // when the user first tapped mic
  Timer? _restartTimer;           // pending auto-restart timer
  String? _lastLoggedError;       // dedup guard for repeated error logs

  // ── Per-session state ──────────────────────────────────────────────────────

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool get isTranscribing => false; // kept for API compat; always false

  bool get isLongDictating => _isLongDictation;

  String _currentPartial = '';

  // Merged live text: accumulated words + current partial.
  // HomeScreen reads this for the live preview — no listener changes needed.
  String get partialText {
    if (_accumulatedText.isEmpty) return _currentPartial;
    if (_currentPartial.isEmpty) return _accumulatedText;
    return '$_accumulatedText $_currentPartial';
  }

  // Only set when the ENTIRE long dictation ends (user stops or 3-min cap).
  String _finalText = '';
  String get finalText => _finalText;

  // Seconds left in the 3-minute cap (for optional UI countdown).
  int get secondsRemaining {
    if (_dictationStart == null || !_isLongDictation) return _totalMaxSecs;
    final elapsed = DateTime.now().difference(_dictationStart!).inSeconds;
    final left = _totalMaxSecs - elapsed;
    return left < 0 ? 0 : left;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Initialise / request permissions. Returns false if unavailable or denied.
  Future<bool> initialize() async {
    _initialized = await _speech.initialize(
      onError: _onError,
      onStatus: _onStatus,
    );
    return _initialized;
  }

  /// Start long dictation. Returns false if permission denied.
  Future<bool> start() async {
    if (_isLongDictation) return true;

    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return false;
    }

    _accumulatedText = '';
    _currentPartial = '';
    _finalText = '';
    _userStopped = false;
    _endedByStop = false;
    _lastLoggedError = null;
    _isLongDictation = true;
    _dictationStart = DateTime.now();

    return _startInternalSession();
  }

  /// Stop dictation (user-initiated). Commits all accumulated text.
  Future<void> stop() async {
    if (!_isRecording && !_isLongDictation) return;
    _userStopped = true;
    _restartTimer?.cancel();
    _restartTimer = null;
    if (_isRecording) await _speech.stop();
    // Commit now if _onResult(final) hasn't already done so.
    if (!_endedByStop) {
      _endedByStop = true;
      _endLongDictation();
    }
  }

  /// Clear text — called by HomeScreen after inserting committed text.
  void clearText() {
    _currentPartial = '';
    _accumulatedText = '';
    _finalText = '';
    notifyListeners();
  }

  Future<void> disposeAll() async {
    _restartTimer?.cancel();
    _speech.cancel();
    _isRecording = false;
    _isLongDictation = false;
    _initialized = false;
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  Future<bool> _startInternalSession() async {
    if (!_isLongDictation || _userStopped) return false;

    final elapsed = _dictationStart == null
        ? _totalMaxSecs
        : DateTime.now().difference(_dictationStart!).inSeconds;

    if (elapsed >= _totalMaxSecs) {
      _endLongDictation();
      return false;
    }

    final remaining = _totalMaxSecs - elapsed;
    final sessionSecs = remaining < _sessionSecs ? remaining : _sessionSecs;

    _currentPartial = '';
    _isRecording = true;
    notifyListeners();

    // listenFor and pauseFor moved into SpeechListenOptions (v7+ API).
    _speech.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenFor: Duration(seconds: sessionSecs),
        pauseFor: const Duration(seconds: _pauseSecs),
      ),
    );

    return true;
  }

  void _endLongDictation() {
    final combined = _accumulatedText.isEmpty
        ? _currentPartial
        : (_currentPartial.isEmpty
            ? _accumulatedText
            : '$_accumulatedText $_currentPartial');
    _finalText = combined.trim();
    _currentPartial = '';
    _isRecording = false;
    _isLongDictation = false;
    notifyListeners();
  }

  // ── Callbacks ──────────────────────────────────────────────────────────────

  void _onResult(SpeechRecognitionResult result) {
    if (result.finalResult) {
      if (_endedByStop) return; // stop() already committed — ignore

      final words = result.recognizedWords.trim();
      _isRecording = false;

      if (_isLongDictation && !_userStopped) {
        final elapsed = _dictationStart == null
            ? _totalMaxSecs
            : DateTime.now().difference(_dictationStart!).inSeconds;

        if (elapsed < _totalMaxSecs) {
          // Auto-restart: accumulate this session's result and schedule next.
          if (words.isNotEmpty) {
            _accumulatedText = _accumulatedText.isEmpty
                ? words
                : '$_accumulatedText $words';
          }
          _currentPartial = '';
          // _finalText intentionally NOT set — HomeScreen must not commit yet.
          // Cancel any restart already queued by _onStatus; we take over here.
          _restartTimer?.cancel();
          if (kDebugMode) debugPrint('[Speech] auto-restart');
          notifyListeners();
          _restartTimer = Timer(
            const Duration(milliseconds: _restartDelayMs),
            () async { await _startInternalSession(); },
          );
          return;
        }
      }

      // Full stop (user-stopped, or 3-minute cap reached): commit everything.
      if (kDebugMode && _userStopped) debugPrint('[Speech] stopped by user');
      _restartTimer?.cancel();
      _restartTimer = null;
      _endedByStop = true;
      final combined = _accumulatedText.isEmpty
          ? words
          : (words.isEmpty ? _accumulatedText : '$_accumulatedText $words');
      _finalText = combined.trim();
      _currentPartial = '';
      _isLongDictation = false;
      notifyListeners();
    } else {
      // Partial result — update live preview.
      _currentPartial = result.recognizedWords;
      notifyListeners();
    }
  }

  void _onStatus(String status) {
    // 'done' / 'notListening' → native engine stopped.
    // Do NOT promote partial → final here; on iOS _onResult(final) fires
    // shortly after and is the authoritative result.
    if ((status == 'done' || status == 'notListening') && _isRecording) {
      _isRecording = false;
      notifyListeners();
      // Safety net for Android builds where _onResult(final) never arrives:
      // schedule a restart if none is already pending. If _onResult(final)
      // does arrive within the delay, it will cancel this and reschedule.
      if (_isLongDictation && !_userStopped && !_endedByStop && _restartTimer == null) {
        _restartTimer = Timer(
          const Duration(milliseconds: _restartDelayMs),
          () async { await _startInternalSession(); },
        );
      }
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (kDebugMode && error.errorMsg != _lastLoggedError) {
      _lastLoggedError = error.errorMsg;
      debugPrint('[Speech] error=${error.errorMsg}');
    }
    _isRecording = false;
    _currentPartial = '';

    // On transient errors during long dictation, retry after a longer delay.
    if (_isLongDictation && !_userStopped && !_endedByStop) {
      final elapsed = _dictationStart == null
          ? _totalMaxSecs
          : DateTime.now().difference(_dictationStart!).inSeconds;
      if (elapsed < _totalMaxSecs) {
        notifyListeners();
        _restartTimer = Timer(
          const Duration(milliseconds: _restartDelayMs * 2),
          () async { await _startInternalSession(); },
        );
        return;
      }
    }

    _isLongDictation = false;
    notifyListeners();
  }
}
