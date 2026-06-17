import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';

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

  group('AppSettingsRepository.autoCheckUpdates', () {
    test('defaults to enabled (opt-out) when nothing stored', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      expect(await repo.loadAutoCheckUpdatesEnabled(), isTrue);
    });

    test('round-trips disabled flag', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      await repo.saveAutoCheckUpdatesEnabled(false);
      expect(await repo.loadAutoCheckUpdatesEnabled(), isFalse);

      await repo.saveAutoCheckUpdatesEnabled(true);
      expect(await repo.loadAutoCheckUpdatesEnabled(), isTrue);
    });
  });

  group('AppSettingsRepository.skippedUpdateVersion', () {
    test('returns null when nothing stored', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      expect(await repo.loadSkippedUpdateVersion(), isNull);
    });

    test('round-trips a skipped version and clears it', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      await repo.saveSkippedUpdateVersion('2.2.0');
      expect(await repo.loadSkippedUpdateVersion(), '2.2.0');

      await repo.saveSkippedUpdateVersion(null);
      expect(await repo.loadSkippedUpdateVersion(), isNull);
    });
  });

  group('AppSettingsRepository.hasCompletedOnboarding', () {
    test('returns false when nothing is stored', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      expect(await repo.loadHasCompletedOnboarding(), isFalse);
    });

    test('round-trips completion flag', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      await repo.saveHasCompletedOnboarding(true);

      expect(await repo.loadHasCompletedOnboarding(), isTrue);
    });

    test('stores alongside llm config override', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      await repo.saveLlmConfigPathOverride('/custom/llm.json');
      await repo.saveHasCompletedOnboarding(true);

      expect(await repo.loadLlmConfigPathOverride(), '/custom/llm.json');
      expect(await repo.loadHasCompletedOnboarding(), isTrue);
    });
  });
}
