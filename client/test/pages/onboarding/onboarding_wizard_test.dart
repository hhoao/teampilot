import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/onboarding/onboarding_wizard.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/app/onboarding_service.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/services/plugin/profile_plugin_linker_service.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

class _NoopPluginLinker extends ProfilePluginLinkerService {
  _NoopPluginLinker() : super(appPluginsRoot: '/tmp');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('onboardingStepsForPlatform', () {
    test('desktop has four steps without workHome', () {
      expect(
        onboardingStepsForPlatform(isAndroid: false),
        [
          OnboardingStepKind.appearance,
          OnboardingStepKind.cli,
          OnboardingStepKind.providerImport,
          OnboardingStepKind.defaultPreset,
        ],
      );
    });

    test('android includes workHome before cli when unbound', () {
      expect(
        onboardingStepsForPlatform(
          isAndroid: true,
          hasBoundAndroidWorkHome: false,
        ),
        [
          OnboardingStepKind.appearance,
          OnboardingStepKind.workHome,
          OnboardingStepKind.cli,
          OnboardingStepKind.providerImport,
          OnboardingStepKind.defaultPreset,
        ],
      );
    });

    test('android skips workHome when already bound', () {
      expect(
        onboardingStepsForPlatform(
          isAndroid: true,
          hasBoundAndroidWorkHome: true,
        ),
        isNot(contains(OnboardingStepKind.workHome)),
      );
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

    test(
      'shows wizard when session preferences exist but onboarding incomplete',
      () async {
        SharedPreferences.setMockInitialValues({
          'flashskyai.session_preferences.v1': '{"connectionMode":"localPty"}',
        });
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPrefsAppSettingsRepository(prefs);
        final service = OnboardingService(appSettings: repo);

        expect(await service.shouldShowOnboarding(), isTrue);
        expect(await repo.loadHasCompletedOnboarding(), isFalse);
      },
    );

    test('skips wizard only when onboarding was completed', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);
      await repo.saveHasCompletedOnboarding(true);
      final service = OnboardingService(appSettings: repo);

      expect(await service.shouldShowOnboarding(), isFalse);
    });
  });

  group('OnboardingService.applyDefaultPreset', () {
    test('applies preset to personal identities and teams', () async {
      final dir = await Directory.systemTemp.createTemp('onboarding-preset_');
      final teamRepo = LaunchProfileRepository(
        rootDir: p.join(dir.path, 'launch-profiles'),
      );
      const team = TeamProfile(
        id: LaunchProfileProvisioner.defaultNativeTeamId,
        name: 'Default Native Team',
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
    test(
      'binds selected claude provider to teams without team binding',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'onboarding-provider-bind_',
        );
        final teamRepo = LaunchProfileRepository(
          rootDir: p.join(dir.path, 'launch-profiles'),
        );
        const team = TeamProfile(
          id: LaunchProfileProvisioner.defaultNativeTeamId,
          name: 'Default Native Team',
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
      },
    );
  });

  group('OnboardingWizard footer gating', () {
    late Directory tempDir;
    late SessionPreferencesCubit sessionPrefs;
    late SshProfileRepository profileRepository;
    late SshProfileCubit profileCubit;
    late LayoutCubit layoutCubit;
    late RuntimeTarget Function() homeResolver;
    late ConnectionModeService mode;

    setUp(() async {
      setUpTestAppStorage();
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('wizard_footer_');
      profileRepository = SshProfileRepository(
        rootDir: tempDir.path,
        fs: InMemoryFilesystem(),
      );
      profileCubit = SshProfileCubit(
        profileRepository: profileRepository,
        credentialStore: InMemorySshCredentialStore(),
      );
      final prefs = await SharedPreferences.getInstance();
      sessionPrefs = SessionPreferencesCubit(
        repository: SessionPreferencesRepository(prefs),
      );
      await sessionPrefs.load();
      layoutCubit = LayoutCubit();
      homeResolver = RuntimeTarget.local;
      mode = ConnectionModeService(
        defaultTargetResolver: () => homeResolver(),
        hasSshProfiles: () => profileCubit.state.hasProfiles,
      );
    });

    tearDown(() async {
      tearDownTestAppStorage();
      await profileCubit.close();
      await sessionPrefs.close();
      await layoutCubit.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> pumpWizard(
      WidgetTester tester, {
      required List<OnboardingStepKind> steps,
      VoidCallback? onComplete,
    }) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final theme = ThemeData(useMaterial3: true);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: theme,
          home: TpTheme(
            data: TpThemeData.fromColorScheme(
              theme.colorScheme,
              scale: 1.0,
              controlScale: AppTypographyScale.standard.multiplier,
            ),
            child: MultiRepositoryProvider(
              providers: [
                RepositoryProvider<ConnectionModeService>.value(value: mode),
              ],
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<SessionPreferencesCubit>.value(
                    value: sessionPrefs,
                  ),
                  BlocProvider<SshProfileCubit>.value(value: profileCubit),
                  BlocProvider<LayoutCubit>.value(value: layoutCubit),
                ],
                child: OnboardingWizard(
                  onComplete: onComplete ?? () {},
                  steps: steps,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    FilledButton primaryButton(WidgetTester tester) {
      return tester.widget<FilledButton>(find.byType(FilledButton));
    }

    testWidgets('workHome step hides Skip and disables Next until bound', (
      tester,
    ) async {
      await pumpWizard(
        tester,
        steps: const [
          OnboardingStepKind.workHome,
          OnboardingStepKind.appearance,
        ],
      );

      expect(find.text('Choose work environment'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(primaryButton(tester).onPressed, isNull);

      const profile = SshProfile(
        id: 'p1',
        name: 'dev',
        host: 'example.com',
        username: 'alice',
      );
      await profileRepository.save(profile);
      await profileCubit.load();
      homeResolver = () => RuntimeTarget.ssh('p1', label: 'box');
      await profileCubit.selectProfile('p1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Auto-advance animates off workHome; settle onto appearance.
      await tester.pumpAndSettle();

      expect(find.text('Skip'), findsOneWidget);
      expect(primaryButton(tester).onPressed, isNotNull);
    });

    testWidgets('Skip still works on appearance', (tester) async {
      await pumpWizard(
        tester,
        steps: const [
          OnboardingStepKind.appearance,
          OnboardingStepKind.workHome,
        ],
      );

      expect(find.text('Skip'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Choose work environment'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(primaryButton(tester).onPressed, isNull);
    });
  });
}
