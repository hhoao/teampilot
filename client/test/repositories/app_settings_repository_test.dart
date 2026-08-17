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
      expect(
        prefs.containsKey(SharedPrefsAppSettingsRepository.storageKey),
        isFalse,
      );
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

  test('InMemory round trip and null-on-empty', () async {
    final repo = InMemoryAppSettingsRepository();
    expect(await repo.loadSkillsMpApiKey(), isNull);
    await repo.saveSkillsMpApiKey('sk_abc');
    expect(await repo.loadSkillsMpApiKey(), 'sk_abc');
    await repo.saveSkillsMpApiKey(null);
    expect(await repo.loadSkillsMpApiKey(), isNull);
  });

  test('InMemory constructor seed', () async {
    final repo = InMemoryAppSettingsRepository(skillsMpApiKey: 'sk_seed');
    expect(await repo.loadSkillsMpApiKey(), 'sk_seed');
  });

  test('SharedPrefs persists key in the settings map', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = SharedPrefsAppSettingsRepository(prefs);
    expect(await repo.loadSkillsMpApiKey(), isNull);
    await repo.saveSkillsMpApiKey('sk_prefs');
    expect(await repo.loadSkillsMpApiKey(), 'sk_prefs');
    await repo.saveSkillsMpApiKey(null);
    expect(await repo.loadSkillsMpApiKey(), isNull);
  });

  group('AppSettingsRepository.discoveryAutoRefresh', () {
    test('defaults to disabled (opt-in) when nothing stored', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      expect(await repo.loadDiscoveryAutoRefreshEnabled(), isFalse);
    });

    test('round-trips enabled flag', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      await repo.saveDiscoveryAutoRefreshEnabled(true);
      expect(await repo.loadDiscoveryAutoRefreshEnabled(), isTrue);

      await repo.saveDiscoveryAutoRefreshEnabled(false);
      expect(await repo.loadDiscoveryAutoRefreshEnabled(), isFalse);
    });
  });

  test('InMemory discoveryAutoRefresh round trip and seed', () async {
    final repo = InMemoryAppSettingsRepository();
    expect(await repo.loadDiscoveryAutoRefreshEnabled(), isFalse);
    await repo.saveDiscoveryAutoRefreshEnabled(true);
    expect(await repo.loadDiscoveryAutoRefreshEnabled(), isTrue);

    final seeded = InMemoryAppSettingsRepository(
      discoveryAutoRefreshEnabled: true,
    );
    expect(await seeded.loadDiscoveryAutoRefreshEnabled(), isTrue);
  });
}
