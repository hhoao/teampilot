import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:teampilot/cubits/app_update_cubit.dart';
import 'package:teampilot/models/app_release_info.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/app/app_update_service.dart';

class _FakeUpdateService extends AppUpdateService {
  _FakeUpdateService({
    required this.result,
    this.versionLabel = '2.1.10',
    this.throwOnCheck = false,
  });

  final AppUpdateCheckResult result;
  final String versionLabel;
  final bool throwOnCheck;
  int checkCalls = 0;

  @override
  Future<String> currentVersionLabel() async => versionLabel;

  @override
  Future<AppUpdateCheckResult> checkForUpdates({bool? preferAndroidArm64}) async {
    checkCalls++;
    if (throwOnCheck) {
      throw AppUpdateException('network down');
    }
    return result;
  }
}

AppReleaseInfo _release(String version) => AppReleaseInfo(
  version: Version.parse(version),
  tagName: 'v$version',
  releaseNotes: '## Updates\n- something',
  downloadUrl: 'https://example.com/app-$version.deb',
  assetName: 'app-$version.deb',
  fileSize: 1234,
  htmlUrl: 'https://github.com/hhoao/teampilot/releases/tag/v$version',
);

void main() {
  group('AppUpdateCubit.autoCheckOnStartup', () {
    test('prompts when an update is available and not skipped', () async {
      final cubit = AppUpdateCubit(
        service: _FakeUpdateService(result: AppUpdateAvailable(_release('2.2.0'))),
        settings: InMemoryAppSettingsRepository(),
      );
      addTearDown(cubit.close);

      await cubit.autoCheckOnStartup();

      expect(cubit.state.status, AppUpdateStatus.available);
      expect(cubit.state.promptRelease?.version.toString(), '2.2.0');
      expect(cubit.state.availableRelease?.version.toString(), '2.2.0');
    });

    test('does not prompt when auto-check is disabled', () async {
      final service = _FakeUpdateService(
        result: AppUpdateAvailable(_release('2.2.0')),
      );
      final cubit = AppUpdateCubit(
        service: service,
        settings: InMemoryAppSettingsRepository(
          autoCheckUpdatesEnabled: false,
        ),
      );
      addTearDown(cubit.close);

      await cubit.autoCheckOnStartup();

      expect(service.checkCalls, 0);
      expect(cubit.state.promptRelease, isNull);
    });

    test('does not prompt for a version the user skipped', () async {
      final cubit = AppUpdateCubit(
        service: _FakeUpdateService(result: AppUpdateAvailable(_release('2.2.0'))),
        settings: InMemoryAppSettingsRepository(skippedUpdateVersion: '2.2.0'),
      );
      addTearDown(cubit.close);

      await cubit.autoCheckOnStartup();

      // Still tracked inline, but no popup prompt.
      expect(cubit.state.availableRelease?.version.toString(), '2.2.0');
      expect(cubit.state.promptRelease, isNull);
    });

    test('prompts for a version newer than the skipped one', () async {
      final cubit = AppUpdateCubit(
        service: _FakeUpdateService(result: AppUpdateAvailable(_release('2.3.0'))),
        settings: InMemoryAppSettingsRepository(skippedUpdateVersion: '2.2.0'),
      );
      addTearDown(cubit.close);

      await cubit.autoCheckOnStartup();

      expect(cubit.state.promptRelease?.version.toString(), '2.3.0');
    });

    test('stays silent when up to date', () async {
      final cubit = AppUpdateCubit(
        service: _FakeUpdateService(result: AppUpdateUpToDate()),
        settings: InMemoryAppSettingsRepository(),
      );
      addTearDown(cubit.close);

      await cubit.autoCheckOnStartup();

      expect(cubit.state.promptRelease, isNull);
      expect(cubit.state.status, isNot(AppUpdateStatus.error));
    });

    test('never surfaces errors on startup', () async {
      final cubit = AppUpdateCubit(
        service: _FakeUpdateService(
          result: AppUpdateUpToDate(),
          throwOnCheck: true,
        ),
        settings: InMemoryAppSettingsRepository(),
      );
      addTearDown(cubit.close);

      await cubit.autoCheckOnStartup();

      expect(cubit.state.status, isNot(AppUpdateStatus.error));
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.promptRelease, isNull);
    });
  });

  group('AppUpdateCubit preference actions', () {
    test('setAutoCheckEnabled persists the toggle', () async {
      final settings = InMemoryAppSettingsRepository();
      final cubit = AppUpdateCubit(
        service: _FakeUpdateService(result: AppUpdateUpToDate()),
        settings: settings,
      );
      addTearDown(cubit.close);

      await cubit.setAutoCheckEnabled(false);

      expect(cubit.state.autoCheckEnabled, isFalse);
      expect(await settings.loadAutoCheckUpdatesEnabled(), isFalse);
    });

    test('skipPromptedVersion clears the prompt and persists the version', () async {
      final settings = InMemoryAppSettingsRepository();
      final cubit = AppUpdateCubit(
        service: _FakeUpdateService(result: AppUpdateAvailable(_release('2.2.0'))),
        settings: settings,
      );
      addTearDown(cubit.close);

      await cubit.autoCheckOnStartup();
      expect(cubit.state.promptRelease, isNotNull);

      await cubit.skipPromptedVersion();

      expect(cubit.state.promptRelease, isNull);
      expect(cubit.state.skippedVersion, '2.2.0');
      expect(await settings.loadSkippedUpdateVersion(), '2.2.0');
    });

    test('consumePrompt clears the one-shot signal only', () async {
      final cubit = AppUpdateCubit(
        service: _FakeUpdateService(result: AppUpdateAvailable(_release('2.2.0'))),
        settings: InMemoryAppSettingsRepository(),
      );
      addTearDown(cubit.close);

      await cubit.autoCheckOnStartup();
      cubit.consumePrompt();

      expect(cubit.state.promptRelease, isNull);
      expect(cubit.state.availableRelease?.version.toString(), '2.2.0');
    });
  });
}
