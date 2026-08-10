import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/compose/compose_text_edit.dart';
import '../../services/compose/compose_voice_input.dart';

/// Extracted voice-recording controller for [SessionChatView].
///
/// Owns the [ComposeVoiceInput] lifecycle, listening state, session clock
/// (1 Hz stopwatch), and sound-level tracking. The host widget injects its
/// compose [TextEditingController] and wires [onNeedsHostRebuild] so the
/// controller can request a widget rebuild when state flips.
class SessionVoiceController extends ChangeNotifier {
  SessionVoiceController({required this.composeController});

  final TextEditingController composeController;
  late final ComposeVoiceInput _voiceInput;

  bool _listening = false;
  double _soundLevel = 0.0;
  bool _discardTranscript = false;
  TextEditingValue? _insertBaseline;
  Stopwatch? _stopwatch;
  Timer? _timer;
  bool _permissionDenied = false;

  /// Set by the host after construction so the controller can trigger a
  /// [setState] on the widget when voice state flips (listening started /
  /// stopped, final transcript inserted).
  VoidCallback? onNeedsHostRebuild;

  // -- public API ----------------------------------------------------------

  bool get isListening => _listening;
  double get soundLevel => _soundLevel;
  Duration get elapsed => _stopwatch?.elapsed ?? Duration.zero;
  bool get isSessionActive => _voiceInput.isSessionActive;
  bool get permissionDenied => _permissionDenied;

  /// Exposed so the host can reach the underlying recognizer if needed.
  ComposeVoiceInput get input => _voiceInput;

  // -- lifecycle -----------------------------------------------------------

  void initialize() {
    _voiceInput = ComposeVoiceInput(
      onFinalTranscript: (text) {
        if (_discardTranscript) return;
        if (_insertBaseline != null) {
          composeController.value = _insertBaseline!;
        }
        composeController.value = insertTextAtSelection(
          composeController,
          text,
          separatorBefore: ' ',
          separatorAfter: ' ',
        );
        _insertBaseline = null;
        onNeedsHostRebuild?.call();
      },
      onListeningChanged: (listening) {
        _applyListening(listening);
      },
      onSoundLevel: (level) {
        _soundLevel = level;
        notifyListeners();
      },
      onError: (error) {
        _permissionDenied = speechRecognitionErrorIsPermissionDenied(error);
        _applyListening(false);
        notifyListeners();
      },
    );
    unawaited(_voiceInput.initialize());
  }

  @override
  void dispose() {
    _stopSessionClock();
    _voiceInput.dispose();
    super.dispose();
  }

  // -- actions -------------------------------------------------------------

  /// Toggles the voice session on or off.
  ///
  /// Returns `true` when a listening session was started or is already active,
  /// so the host can request focus. Returns `false` when recognition is
  /// unavailable (host should check [permissionDenied] for the reason) or when
  /// the session was stopped.
  Future<bool> toggle(Locale preferredLocale) async {
    final available = await _voiceInput.initialize();
    if (!available) {
      _permissionDenied = _voiceInput.permissionDenied;
      notifyListeners();
      return false;
    }

    final started = await _voiceInput.toggleListening(
      preferredLocale: preferredLocale,
    );
    if (!started && !_voiceInput.isSessionActive) return false;
    return true;
  }

  /// Discards the current voice session without inserting the transcript.
  Future<void> cancel() async {
    if (!_listening && !_voiceInput.isSessionActive) return;
    _discardTranscript = true;
    await _voiceInput.endSession(discard: true);
  }

  /// Stops the current voice session and inserts the final transcript.
  Future<void> stop() async {
    if (!_listening && !_voiceInput.isSessionActive) return;
    _discardTranscript = false;
    await _voiceInput.endSession(discard: false);
  }

  // -- internals -----------------------------------------------------------

  void _applyListening(bool listening) {
    if (listening) {
      _discardTranscript = false;
      _insertBaseline ??= composeController.value;
      final needsRebuild = !_listening || _stopwatch == null;
      _listening = true;
      if (_stopwatch == null) _startSessionClock();
      if (needsRebuild) onNeedsHostRebuild?.call();
      return;
    }
    if (!_listening && _stopwatch == null) return;
    if (_discardTranscript) {
      _insertBaseline = null;
    }
    _listening = false;
    _stopSessionClock();
    onNeedsHostRebuild?.call();
  }

  void _startSessionClock() {
    _stopwatch = Stopwatch()..start();
    _soundLevel = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  void _stopSessionClock() {
    _timer?.cancel();
    _timer = null;
    _stopwatch?.stop();
    _stopwatch = null;
    _soundLevel = 0;
  }
}
