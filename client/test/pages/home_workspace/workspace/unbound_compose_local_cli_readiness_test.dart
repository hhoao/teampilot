import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/local_cli_readiness_banner.dart';
import 'package:teampilot/pages/home_workspace/workspace/unbound_compose_body.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_draft_cache.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/widgets/compose/workspace_compose_card.dart';

import '../../../support/post_frame_test_harness.dart';
import '../../../support/compose_field_test_utils.dart';

class _MockChatCubit extends Mock implements ChatCubit {}

class _MockAppProviderCubit extends Mock implements AppProviderCubit {}

class _MockCliPresetsCubit extends Mock implements CliPresetsCubit {}

class _MockLaunchProfileCubit extends Mock implements LaunchProfileCubit {}

class _MockPluginCubit extends Mock implements PluginCubit {}

class _MockSkillCubit extends Mock implements SkillCubit {}

class _MockWorktreeCubit extends Mock implements WorktreeCubit {}

void _stubCubit<TState>(Cubit<TState> cubit, TState state) {
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => Stream<TState>.empty());
}

Future<SessionPreferencesCubit> _prefsCubit({
  Map<CliTool, String> locatedExecutables = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final cubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(prefs),
    locatedExecutables: locatedExecutables,
  );
  await cubit.load();
  cubit.markLocalDiscoveryCompleted();
  return cubit;
}

Future<void> _pumpLanding(
  WidgetTester tester, {
  required Workspace workspace,
  required SessionPreferencesCubit sessionPreferencesCubit,
  required void Function() onSubmit,
  RemoteCliReadinessService? readiness,
}) async {
  final chatCubit = _MockChatCubit();
  final appProviderCubit = _MockAppProviderCubit();
  final cliPresetsCubit = _MockCliPresetsCubit();
  final launchProfileCubit = _MockLaunchProfileCubit();
  final pluginCubit = _MockPluginCubit();
  final skillCubit = _MockSkillCubit();
  final worktreeCubit = _MockWorktreeCubit();

  _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
  when(() => chatCubit.remoteCliReadiness).thenReturn(readiness);
  _stubCubit(appProviderCubit, const AppProviderState());
  _stubCubit(cliPresetsCubit, const CliPresetsState());
  _stubCubit(launchProfileCubit, const LaunchProfileState());
  _stubCubit(pluginCubit, const PluginState());
  _stubCubit(skillCubit, const SkillState());
  _stubCubit(worktreeCubit, const WorktreeState());
  when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);
  when(
    () => worktreeCubit.selectProject(
      any(),
      preferWorktreePath: any(named: 'preferWorktreePath'),
    ),
  ).thenAnswer((_) async {});

  final theme = buildDarkTheme();
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
        RepositoryProvider<HomeStorage>.value(value: testHomeStorage),
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
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: appLocalizationsSupportedLocales,
            home: TpTheme(
              data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
              child: Scaffold(
                body: UnboundComposeBody(
                  workspace: workspace,
                  onSubmit: (_, __) => onSubmit(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Remote readiness probe that never resolves until the test releases it.
class _BlockingReadiness extends RemoteCliReadinessService {
  _BlockingReadiness()
    : super(
        registry: CliToolRegistry.builtIn(),
        sshClientFactory: _ThrowingSshClientFactory(),
        profileById: (_) => null,
        cliPathOverride: (_, __) async => null,
        setCliPathOverride: (_, __, ___) async {},
      );

  final release = Completer<RemoteCliReadiness>();

  @override
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) => release.future;
}

class _ThrowingSshClientFactory implements SshClientFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Workspace _localWorkspace() => Workspace(
  workspaceId: 'workspace-1',
  folders: const [WorkspaceFolder(path: '/repo', targetId: 'local')],
  createdAt: 1,
);

void main() {
  setUp(() {
    setUpTestAppStorage();
    composeDraftCache.clear();
  });
  tearDown(tearDownTestAppStorage);

  testWidgets(
    'blocks send and shows the banner when the local CLI is missing',
    (tester) async {
      var submitted = 0;
      await _pumpLanding(
        tester,
        workspace: _localWorkspace(),
        sessionPreferencesCubit: await _prefsCubit(),
        onSubmit: () => submitted++,
      );

      expect(find.byType(LocalCliReadinessBanner), findsOneWidget);
      // Inline actions mirror the remote readiness panel (no Settings detour).
      expect(find.text('Install'), findsOneWidget);
      expect(find.text('Locate'), findsOneWidget);

      await enterComposeText(tester, 'hello');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(submitted, 0);
    },
  );

  testWidgets('allows send when the local CLI is known', (tester) async {
    var submitted = 0;
    await _pumpLanding(
      tester,
      workspace: _localWorkspace(),
      sessionPreferencesCubit: await _prefsCubit(
        locatedExecutables: const {CliTool.claude: '/usr/local/bin/claude'},
      ),
      onSubmit: () => submitted++,
    );

    expect(find.byType(LocalCliReadinessBanner), findsNothing);

    await enterComposeText(tester, 'hello');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(submitted, 1);
  });

  testWidgets(
    'send shows the submitting state before the remote readiness probe returns',
    (tester) async {
      final workspace = Workspace(
        workspaceId: 'workspace-1',
        folders: const [
          WorkspaceFolder(path: '/remote', targetId: 'ssh:host-a'),
        ],
        createdAt: 1,
      );
      final readiness = _BlockingReadiness();
      var submitted = 0;

      await _pumpLanding(
        tester,
        workspace: workspace,
        sessionPreferencesCubit: await _prefsCubit(
          locatedExecutables: const {CliTool.claude: '/usr/local/bin/claude'},
        ),
        readiness: readiness,
        onSubmit: () => submitted++,
      );

      await enterComposeText(tester, 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      // The tap must flip the button into its submitting state immediately,
      // while the (network-backed) readiness probe is still in flight.
      expect(
        tester
            .widget<WorkspaceComposeCard>(find.byType(WorkspaceComposeCard))
            .isSubmitting,
        isTrue,
      );
      expect(submitted, 0);

      readiness.release.complete(
        RemoteCliReady(
          targetId: 'ssh:host-a',
          cli: CliTool.claude,
          path: '/usr/local/bin/claude',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(submitted, 1);
      expect(
        tester
            .widget<WorkspaceComposeCard>(find.byType(WorkspaceComposeCard))
            .isSubmitting,
        isFalse,
      );
    },
  );
}
