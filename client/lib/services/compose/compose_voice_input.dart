import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../l10n/app_localizations.dart';
import 'compose_voice_platform.dart';

typedef ComposeVoiceTranscript = void Function(String text);
typedef ComposeVoiceErrorHandler = void Function(SpeechRecognitionError error);
typedef ComposeVoiceSoundLevel = void Function(double level);

/// Whether [error] indicates the user denied microphone / speech permission.
/// User-facing message after a failed [ComposeVoiceInput.initialize].
String composeVoiceInitFailureMessage(
  AppLocalizations l10n,
  ComposeVoiceInput input,
) {
  if (input.blockedByMacOsIdeLaunch) {
    return l10n.workspaceChatLandingVoiceMacOsIdeLaunch;
  }
  if (input.permissionDenied) {
    return l10n.workspaceChatLandingVoicePermissionDenied;
  }
  return l10n.workspaceChatLandingVoiceUnavailable;
}

/// Whether [error] indicates the user denied microphone / speech permission.
bool speechRecognitionErrorIsPermissionDenied(SpeechRecognitionError error) {
  final msg = error.errorMsg.toLowerCase();
  return msg.contains('permission') ||
      msg.contains('denied') ||
      msg.contains('not authorized') ||
      msg.contains('error_permission');
}

/// Picks the best speech locale for [preferred] from [available].
String? resolveSpeechLocaleId({
  required List<LocaleName> available,
  required Locale preferred,
}) {
  if (available.isEmpty) return null;

  final ids = available.map((locale) => locale.localeId).toList(growable: false);
  final country = preferred.countryCode;
  if (country != null && country.isNotEmpty) {
    final canonical = '${preferred.languageCode}-$country';
    if (ids.contains(canonical)) return canonical;
  }

  if (preferred.languageCode == 'zh') {
    for (final candidate in ['zh-CN', 'zh-TW', 'zh-HK', 'cmn-Hans-CN']) {
      if (ids.contains(candidate)) return candidate;
    }
  }

  for (final id in ids) {
    if (id == preferred.languageCode ||
        id.startsWith('${preferred.languageCode}-')) {
      return id;
    }
  }

  return ids.first;
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
  var _blockedByMacOsIdeLaunch = false;
  var _sessionActive = false;
  final List<String> _finalSegments = [];
  var _latestPartial = '';

  bool get isListening => _sessionActive || _speech.isListening;
  bool get isSessionActive => _sessionActive;
  bool get isAvailable => _available;
  bool get permissionDenied => _permissionDenied;
  bool get blockedByMacOsIdeLaunch => _blockedByMacOsIdeLaunch;

  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;
    if (!isComposeVoiceMacOsLaunchUsable) {
      _blockedByMacOsIdeLaunch = true;
      _available = false;
      return false;
    }
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

  Future<bool> toggleListening({
    Locale? preferredLocale,
    String? localeId,
  }) async {
    if (!_available) return false;
    if (_sessionActive) {
      await endSession(discard: false);
      return false;
    }
    return start(preferredLocale: preferredLocale, localeId: localeId);
  }

  Future<bool> start({
    Locale? preferredLocale,
    String? localeId,
  }) async {
    if (!_available || _sessionActive) return false;
    _clearSessionBuffers();
    final resolvedLocale =
        localeId ?? await _resolveLocale(preferredLocale: preferredLocale);
    try {
      await _speech.listen(
        onResult: _onResult,
        onSoundLevelChange: onSoundLevel,
        listenOptions: SpeechListenOptions(
          localeId: resolvedLocale,
          listenMode: ListenMode.dictation,
          partialResults: true,
          // Dictation pauses are common; default pauseFor is too aggressive.
          pauseFor: const Duration(seconds: 4),
          listenFor: const Duration(minutes: 5),
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
      } else {
        // Always try stop first; on Windows isListening is often stale.
        try {
          await _speech.stop();
        } on Object {
          // Fall through to cancel below.
        }
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (_speech.isListening) {
          await _speech.cancel();
        }
      }
    } on Object {
      try {
        await _speech.cancel();
      } on Object {
        // Best-effort cleanup.
      }
    }

    final sessionText = discard ? '' : _composeSessionText();
    if (!discard && sessionText.isNotEmpty) {
      onFinalTranscript(sessionText);
    }
    _clearSessionBuffers();
    onListeningChanged?.call(false);
  }

  void dispose() {
    unawaited(endSession(discard: true));
    _speech.cancel();
  }

  Future<String?> _resolveLocale({Locale? preferredLocale}) async {
    final locales = await _speech.locales();
    if (preferredLocale != null) {
      return resolveSpeechLocaleId(
        available: locales,
        preferred: preferredLocale,
      );
    }
    final system = await _speech.systemLocale();
    return system?.localeId ?? (locales.isEmpty ? null : locales.first.localeId);
  }

  void _handleError(SpeechRecognitionError error) {
    if (speechRecognitionErrorIsPermissionDenied(error)) {
      _permissionDenied = true;
      _available = false;
    }
    _sessionActive = false;
    _clearSessionBuffers();
    onError?.call(error);
    unawaited(
      _speech.cancel().catchError((_) {
        // Ignore cleanup errors after a recognition failure.
      }),
    );
    onListeningChanged?.call(false);
  }

  void _onResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;

    if (result.finalResult) {
      if (_finalSegments.isEmpty || _finalSegments.last != words) {
        _finalSegments.add(words);
      }
      _latestPartial = '';
    } else {
      _latestPartial = words;
    }
  }

  String _composeSessionText() {
    final parts = <String>[..._finalSegments];
    if (_latestPartial.isNotEmpty &&
        (_finalSegments.isEmpty || _finalSegments.last != _latestPartial)) {
      parts.add(_latestPartial);
    }
    return parts.join(' ');
  }

  void _clearSessionBuffers() {
    _finalSegments.clear();
    _latestPartial = '';
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
