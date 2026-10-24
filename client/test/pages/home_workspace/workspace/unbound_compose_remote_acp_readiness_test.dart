import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/unbound_compose_body.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_draft_cache.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';
import 'package:teampilot/theme/app_theme.dart';

import '../../../support/in_memory_filesystem.dart';
import '../../../support/post_frame_test_harness.dart';

class _MockChatCubit extends Mock implements ChatCubit {}

class _MockAppProviderCubit extends Mock implements AppProviderCubit {}

class _MockCliPresetsCubit extends Mock implements CliPresetsCubit {}

class _MockLaunchProfileCubit extends Mock implements LaunchProfileCubit {}

class _MockPluginCubit extends Mock implements PluginCubit {}

class _MockSessionPreferencesCubit extends Mock
    implements SessionPreferencesCubit {}

class _MockSkillCubit extends Mock implements SkillCubit {}

class _MockWorktreeCubit extends Mock implements WorktreeCubit {}

void _stubCubit<TState>(Cubit<TState> cubit, TState state) {
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => Stream<TState>.empty());
}

CliPreset _preset(String id, CliTool cli) => CliPreset(
  id: id,
  name: id,
  cli: cli,
  provider: '',
  model: '',
  createdAt: 1,
  updatedAt: 1,
);

/// Remote host that has the CLI but not the separate ACP adapter.
class _AdapterMissingReadiness extends RemoteCliReadinessService {
  _AdapterMissingReadiness()
    : super(
        registry: CliToolRegistry.builtIn(),
        sshClientFactory: _ThrowingSshClientFactory(),
        profileById: (_) => null,
        cliPathOverride: (_, __) async => null,
        setCliPathOverride: (_, __, ___) async {},
      );

  @override
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async {
    if (kind == CliBinaryKind.adapter) {
      return RemoteCliMissing(targetId: target.id, cli: cli);
    }
    return RemoteCliReady(
      targetId: target.id,
      cli: cli,
      path: '/home/u/.local/bin/${cli.value}',
    );
  }
}

class _ThrowingSshClientFactory implements SshClientFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<HomeTargetController> _controllerWithSshProfile() async {
  const root = '/tp-test-remote-acp';
  final fs = InMemoryFilesystem();
  final sshRepo = SshProfileRepository(
    rootDir: root,
    fs: fs,
    storage: fakeHomeStorage(filesystem: fs),
  );
  await sshRepo.save(
    const SshProfile(
      id: 'host-a',
      name: 'Build host',
      host: 'host',
      username: 'u',
    ),
  );
  return HomeTargetController(
    registry: RuntimeTargetRegistry(
      repo: TargetsRepository(rootDir: root, fs: fs),
      sshProfileRepo: sshRepo,
      isWindows: false,
      isAndroid: false,
    ),
    current: RuntimeTarget.local,
    switchTo: (_) async {},
  );
}

void main() {
  setUp(() {
    setUpTestAppStorage();
    composeDraftCache.clear();
  });
  tearDown(tearDownTestAppStorage);

  testWidgets(
    'remote project + Claude ACP shows the missing-adapter readiness panel',
    (tester) async {
      final workspace = Workspace(
        workspaceId: 'workspace-1',
        folders: const [
          WorkspaceFolder(path: '/remote', targetId: 'ssh:host-a'),
        ],
        createdAt: 1,
      );
      final controller = await _controllerWithSshProfile();
      final chatCubit = _MockChatCubit();
      final appProviderCubit = _MockAppProviderCubit();
      final cliPresetsCubit = _MockCliPresetsCubit();
      final launchProfileCubit = _MockLaunchProfileCubit();
      final pluginCubit = _MockPluginCubit();
      final sessionPreferencesCubit = _MockSessionPreferencesCubit();
      final skillCubit = _MockSkillCubit();
      final worktreeCubit = _MockWorktreeCubit();

      _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
      _stubCubit(appProviderCubit, const AppProviderState());
      _stubCubit(
        cliPresetsCubit,
        CliPresetsState(presets: [_preset('preset-1', CliTool.claude)]),
      );
      _stubCubit(launchProfileCubit, const LaunchProfileState());
      _stubCubit(pluginCubit, const PluginState());
      _stubCubit(
        sessionPreferencesCubit,
        SessionPreferencesState(
          preferences: SessionPreferences(claudePersonalAcpDefault: true),
        ),
      );
      _stubCubit(skillCubit, const SkillState());
      _stubCubit(worktreeCubit, const WorktreeState());
      when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);
      when(
        () => worktreeCubit.selectProject(
          any(),
          preferWorktreePath: any(named: 'preferWorktreePath'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => chatCubit.remoteCliReadiness,
      ).thenReturn(_AdapterMissingReadiness());

      final theme = buildDarkTheme();
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
            RepositoryProvider<HomeStorage>.value(value: testHomeStorage),
            RepositoryProvider<HomeTargetController>.value(value: controller),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ChatCubit>.value(value: chatCubit),
              BlocProvider<AppProviderCubit>.value(value: appProviderCubit),
              BlocProvider<CliPresetsCubit>.value(value: cliPresetsCubit),
              BlocProvider<LaunchProfileCubit>.value(value: launchProfileCubit),
              BlocProvider<PluginCubit>.value(value: pluginCubit),
              BlocProvider<SessionPreferencesCubit>.value(
                value: sessionPreferencesCubit,
              ),
              BlocProvider<SkillCubit>.value(value: skillCubit),
              BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
            ],
            child: CliToolRegistryScope(
              registry: CliToolRegistry.builtIn(),
              child: MaterialApp(
                theme: theme,
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: TpTheme(
                  data: TpThemeData.fromColorScheme(
                    theme.colorScheme,
                    scale: 1,
                  ),
                  child: Scaffold(
                    body: UnboundComposeBody(
                      workspace: workspace,
                      onSubmit: (_, __) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Landing draft hydration + runtime-target load + readiness probe.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(
        find.text('Required CLIs on this machine'),
        findsOneWidget,
        reason: 'missing remote ACP adapter should surface the readiness panel',
      );
      expect(find.text('Claude Code ACP adapter'), findsOneWidget);
    },
  );
}
