import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/team_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/onboarding/onboarding_wizard.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/team_repository.dart';
import 'package:teampilot/services/app/onboarding_service.dart';
import 'package:teampilot/services/plugin/identity_plugin_linker_service.dart';

class _NoopPluginLinker extends IdentityPluginLinkerService {
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

  group('OnboardingService.applyDefaultClaudeProviderBinding', () {
    test('binds selected claude provider to teams without team binding', () async {
      final dir = await Directory.systemTemp.createTemp('onboarding-provider-bind_');
      final teamRepo = TeamRepository(rootDir: p.join(dir.path, 'identities'));
      const team = TeamIdentity(
        id: 'default-team',
        name: 'Default Team',
        cli: CliTool.claude,
        members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      );
      await teamRepo.saveTeams([team]);

      final teamCubit = TeamCubit(
        repository: teamRepo,
        sessionRepository: SessionRepository(),
        reloadProjects: () async {},
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
