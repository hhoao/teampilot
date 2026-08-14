import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/onboarding/steps/cli_step.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onboarding CLI step covers every launchable tool', () {
    final registry = CliToolRegistry.builtIn();
    final launchable = registry.launchable.map((d) => d.id).toSet();

    expect(
      launchable,
      containsAll({
        CliTool.claude,
        CliTool.codex,
        CliTool.opencode,
        CliTool.cursor,
        CliTool.flashskyai,
      }),
    );

    expect(
      registry.capability<CliExecutableCapability>(CliTool.claude)?.supportsInstaller,
      isTrue,
    );
    expect(
      registry
          .capability<CliExecutableCapability>(CliTool.flashskyai)
          ?.supportsInstaller,
      isFalse,
    );
  });

  group('OnboardingCliStep remote detect', () {
    late Directory tempDir;
    late SessionPreferencesCubit sessionPrefs;
    late SshProfileRepository profileRepository;
    late SshProfileCubit profileCubit;
    late List<String> storageLookups;
    late SshClientFactory factory;
    late RuntimeTarget Function() homeResolver;
    late ConnectionModeService mode;

    setUp(() async {
      setUpTestAppStorage();
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('cli_step_remote_');
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

      storageLookups = <String>[];
      factory = SshClientFactory(
        credentialStore: InMemorySshCredentialStore(),
        knownHostRepository: InMemorySshKnownHostRepository(),
        connector: (profile, {timeout = const Duration(seconds: 10)}) async {
          storageLookups.add(profile.id);
          throw StateError('spy-remote-locate:${profile.id}');
        },
      );

      homeResolver = () => RuntimeTarget.ssh('p1', label: 'box');
      mode = ConnectionModeService(
        defaultTargetResolver: () => homeResolver(),
        hasSshProfiles: () => profileCubit.state.hasProfiles,
      );

      const profile = SshProfile(
        id: 'p1',
        name: 'dev',
        host: 'example.com',
        username: 'alice',
      );
      await profileRepository.save(profile);
      await profileCubit.load();
      await profileCubit.selectProfile('p1');
    });

    tearDown(() async {
      tearDownTestAppStorage();
      await profileCubit.close();
      await sessionPrefs.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> pumpCliStep(WidgetTester tester) async {
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
                RepositoryProvider<SshClientFactory>.value(value: factory),
              ],
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<SessionPreferencesCubit>.value(
                    value: sessionPrefs,
                  ),
                  BlocProvider<SshProfileCubit>.value(value: profileCubit),
                ],
                child: const Scaffold(
                  body: SingleChildScrollView(
                    child: OnboardingCliStep(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Post-frame detect + async remote client lookup.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets(
      'bound SSH home uses remote locate (not local) on detect',
      (tester) async {
        expect(mode.isRemoteWorkPlane, isTrue);
        await pumpCliStep(tester);

        expect(storageLookups, ['p1']);
        expect(find.textContaining('spy-remote-locate:p1'), findsOneWidget);
      },
    );

    testWidgets('local home does not open SSH client for detect', (
      tester,
    ) async {
      homeResolver = RuntimeTarget.local;
      expect(mode.isRemoteWorkPlane, isFalse);

      await pumpCliStep(tester);

      expect(storageLookups, isEmpty);
    });
  });
}
