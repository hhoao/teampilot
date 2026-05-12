import 'package:flashskyai_client/repositories/app_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppSettingsRepository.llmConfigPathOverride', () {
    test('returns null when nothing is stored', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      expect(await repo.loadLlmConfigPathOverride(), isNull);
    });

    test('round-trips a path', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      await repo.saveLlmConfigPathOverride('/custom/llm.json');

      expect(await repo.loadLlmConfigPathOverride(), '/custom/llm.json');
    });

    test('clearing with null removes the override', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      await repo.saveLlmConfigPathOverride('/custom/llm.json');
      await repo.saveLlmConfigPathOverride(null);

      expect(await repo.loadLlmConfigPathOverride(), isNull);
      expect(prefs.containsKey(SharedPrefsAppSettingsRepository.storageKey), isFalse);
    });

    test('clearing with empty string removes the override', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      await repo.saveLlmConfigPathOverride('/custom/llm.json');
      await repo.saveLlmConfigPathOverride('   ');

      expect(await repo.loadLlmConfigPathOverride(), isNull);
    });

    test('treats non-JSON storage as empty', () async {
      SharedPreferences.setMockInitialValues({
        SharedPrefsAppSettingsRepository.storageKey: 'not json',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      expect(await repo.loadLlmConfigPathOverride(), isNull);
    });
  });
}
