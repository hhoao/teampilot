import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:teampilot/services/compose/compose_voice_input.dart';

void main() {
  group('resolveSpeechLocaleId', () {
    final available = [
      LocaleName('en-US', 'English (United States)'),
      LocaleName('zh-CN', 'Chinese (Simplified)'),
      LocaleName('zh-TW', 'Chinese (Traditional)'),
    ];

    test('prefers exact language-country match', () {
      expect(
        resolveSpeechLocaleId(
          available: available,
          preferred: const Locale('zh', 'CN'),
        ),
        'zh-CN',
      );
    });

    test('maps zh language to zh-CN when country is absent', () {
      expect(
        resolveSpeechLocaleId(
          available: available,
          preferred: const Locale('zh'),
        ),
        'zh-CN',
      );
    });

    test('falls back to first locale when no match', () {
      expect(
        resolveSpeechLocaleId(
          available: [LocaleName('en-US', 'English (United States)')],
          preferred: const Locale('ja', 'JP'),
        ),
        'en-US',
      );
    });
  });

  group('ComposeVoiceInput', () {
    test('starts unavailable until initialize', () {
      final input = ComposeVoiceInput(onFinalTranscript: (_) {});
      expect(input.isAvailable, isFalse);
      expect(input.blockedByMacOsIdeLaunch, isFalse);
      input.dispose();
    });
  });
}
