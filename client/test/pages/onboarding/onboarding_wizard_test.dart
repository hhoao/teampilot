import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/onboarding/onboarding_wizard.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/services/app/onboarding_service.dart';
import 'package:teampilot/services/plugin/profile_plugin_linker_service.dart';
import '../../support/in_memory_filesystem.dart';

class _NoopPluginLinker extends ProfilePluginLinkerService {
  _NoopPluginLinker() : super(appPluginsRoot: '/tmp');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('onboardingStepsForPlatform', () {
    test('desktop has four steps without SSH', () {
      expect(onboardingStepsForPlatform(), hasLength(4));
      expect(onboardingStepsForPlatform(), isNot(contains(OnboardingStepKind.ssh)));
    });
  });

  group('OnboardingService', () {
    test('shows wizard for fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = OnboardingService(
        appSettings: SharedPrefsAppSettingsRepository(prefs),
      );

      expect(await service.shouldShowOnboarding(), isTrue);
    });

    test('shows wizard when session preferences exist but onboarding incomplete', () async {
      SharedPreferences.setMockInitialValues({
        'flashskyai.session_preferences.v1': '{"connectionMode":"localPty"}',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);
      final service = OnboardingService(
        appSettings: repo,
      );

      expect(await service.shouldShowOnboarding(), isTrue);
      expect(await repo.loadHasCompletedOnboarding(), isFalse);
    });

    test('skips wizard only when onboarding was completed', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);
      await repo.saveHasCompletedOnboarding(true);
      final service = OnboardingService(
        appSettings: repo,
      );

      expect(await service.shouldShowOnboarding(), isFalse);
    });
  });

  group('OnboardingService.applyDefaultPreset', () {
    test('applies preset to personal identities and teams', () async {
      final dir = await Directory.systemTemp.createTemp('onboarding-preset_');
      final teamRepo = LaunchProfileRepository(rootDir: p.join(dir.path, 'launch-profiles'));
      const team = TeamProfile(
        id: 'default-team',
        name: 'Default Team',
        cli: CliTool.claude,
        members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      );
      await teamRepo.saveTeamProfiles([team]);

      final presetsRepo = CliPresetsRepository(
        fs: InMemoryFilesystem(),
        presetsPath: p.join(dir.path, 'cli-presets.json'),
      );
      final presetsCubit = CliPresetsCubit(repository: presetsRepo);
      await presetsCubit.addPreset(
        name: 'Default',
        cli: CliTool.claude,
        provider: 'deepseek',
        model: 'deepseek-chat',
      );
      final presetId = presetsCubit.state.presets.single.id;

      final teamCubit = LaunchProfileCubit(
        repository: teamRepo,
        sessionRepository: SessionRepository(),
        executableResolver: () => 'claude',
        pluginLinker: _NoopPluginLinker(),
      );
      await teamCubit.load();

      final appProviderCubit = AppProviderCubit(basePath: dir.path);
      await appProviderCubit.load();
      await appProviderCubit.upsertProvider(
        const AppProviderConfig(
          id: 'deepseek',
          cli: CliTool.claude,
          name: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com/anthropic',
          defaultModel: 'deepseek-chat',
        ),
      );

      await OnboardingService.applyDefaultPreset(
        presetId: presetId,
        cliPresetsCubit: presetsCubit,
        launchProfileCubit: teamCubit,
        appProviderCubit: appProviderCubit,
      );

      expect(teamCubit.state.selectedTeam!.activePresetId, presetId);
      expect(
        appProviderCubit.state.selectedProviderIdByCli[CliTool.claude],
        'deepseek',
      );

      await appProviderCubit.close();
      await teamCubit.close();
      await presetsCubit.close();
      await dir.delete(recursive: true);
    });
  });

  group('OnboardingService.applyDefaultClaudeProviderBinding', () {
    test('binds selected claude provider to teams without team binding', () async {
      final dir = await Directory.systemTemp.createTemp('onboarding-provider-bind_');
      final teamRepo = LaunchProfileRepository(rootDir: p.join(dir.path, 'launch-profiles'));
      const team = TeamProfile(
        id: 'default-team',
        name: 'Default Team',
        cli: CliTool.claude,
        members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      );
      await teamRepo.saveTeamProfiles([team]);

      final teamCubit = LaunchProfileCubit(
        repository: teamRepo,
        sessionRepository: SessionRepository(),
        executableResolver: () => 'claude',
        pluginLinker: _NoopPluginLinker(),
      );
      await teamCubit.load();

      final appProviderCubit = AppProviderCubit(basePath: dir.path);
      await appProviderCubit.load();
      await appProviderCubit.upsertProvider(
        const AppProviderConfig(
          id: 'deepseek',
          cli: CliTool.claude,
          name: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com/anthropic',
          defaultModel: 'deepseek-chat',
        ),
      );
      appProviderCubit.selectProvider('deepseek');

      await OnboardingService.applyDefaultClaudeProviderBinding(
        appProviderCubit: appProviderCubit,
        teamCubit: teamCubit,
      );

      expect(
        teamCubit.state.selectedTeam!.providerIdsByTool['claude'],
        'deepseek',
      );

      await appProviderCubit.close();
      await teamCubit.close();
      await dir.delete(recursive: true);
    });
  });
}
