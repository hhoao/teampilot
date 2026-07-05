import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

typedef ComposeVoiceTranscript = void Function(String text);
typedef ComposeVoiceErrorHandler = void Function(SpeechRecognitionError error);
typedef ComposeVoiceSoundLevel = void Function(double level);

/// Whether [error] indicates the user denied microphone / speech permission.
bool speechRecognitionErrorIsPermissionDenied(SpeechRecognitionError error) {
  final msg = error.errorMsg.toLowerCase();
  return msg.contains('permission') ||
      msg.contains('denied') ||
      msg.contains('not authorized') ||
      msg.contains('error_permission');
}

/// Thin wrapper around [SpeechToText] for landing compose dictation.
///
/// Tracks a local [_sessionActive] flag because platform [SpeechToText.isListening]
/// and status callbacks are unreliable on some desktops (notably Windows).
class ComposeVoiceInput {
  ComposeVoiceInput({
    required this.onFinalTranscript,
    this.onListeningChanged,
    this.onError,
    this.onSoundLevel,
  });

  final ComposeVoiceTranscript onFinalTranscript;
  final ValueChanged<bool>? onListeningChanged;
  final ComposeVoiceErrorHandler? onError;
  final ComposeVoiceSoundLevel? onSoundLevel;

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _available = false;
  var _permissionDenied = false;
  var _sessionActive = false;

  bool get isListening => _sessionActive || _speech.isListening;
  bool get isSessionActive => _sessionActive;
  bool get isAvailable => _available;
  bool get permissionDenied => _permissionDenied;

  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _speech.initialize(
        onStatus: _onStatus,
        onError: _handleError,
      );
    } on Object {
      _available = false;
    }
    return _available;
  }

  Future<bool> toggleListening({String? localeId}) async {
    if (!_available) return false;
    if (_sessionActive) {
      await endSession(discard: false);
      return false;
    }
    return start(localeId: localeId);
  }

  Future<bool> start({String? localeId}) async {
    if (!_available || _sessionActive) return false;
    try {
      await _speech.listen(
        onResult: _onResult,
        onSoundLevelChange: onSoundLevel,
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenMode: ListenMode.dictation,
          partialResults: true,
        ),
      );
    } on Object {
      return false;
    }
    _sessionActive = true;
    onListeningChanged?.call(true);
    return true;
  }

  /// Stops listening and finalizes recognition for insertion.
  Future<void> endSession({required bool discard}) async {
    if (!_sessionActive && !_speech.isListening) return;
    _sessionActive = false;
    try {
      if (discard) {
        await _speech.cancel();
      } else if (_speech.isListening) {
        await _speech.stop();
      } else {
        await _speech.cancel();
      }
    } on Object {
      try {
        await _speech.cancel();
      } on Object {
        // Best-effort cleanup.
      }
    }
    onListeningChanged?.call(false);
  }

  void dispose() {
    unawaited(endSession(discard: true));
    _speech.cancel();
  }

  void _handleError(SpeechRecognitionError error) {
    if (speechRecognitionErrorIsPermissionDenied(error)) {
      _permissionDenied = true;
      _available = false;
    }
    _sessionActive = false;
    onError?.call(error);
    unawaited(
      _speech.cancel().catchError((_) {
        // Ignore cleanup errors after a recognition failure.
      }),
    );
    onListeningChanged?.call(false);
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!result.finalResult) return;
    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;
    onFinalTranscript(words);
  }

  void _onStatus(String status) {
    if (status == SpeechToText.listeningStatus) {
      if (!_sessionActive) {
        _sessionActive = true;
        onListeningChanged?.call(true);
      }
      return;
    }
    if (status == SpeechToText.notListeningStatus ||
        status == SpeechToText.doneStatus) {
      if (_sessionActive) {
        _sessionActive = false;
        onListeningChanged?.call(false);
      }
    }
  }
}
