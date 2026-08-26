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
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';

import '../../support/post_frame_test_harness.dart';

class _FakeRefreshableCapability implements RefreshableProviderModelCapability {
  final ChangeNotifier updates = ChangeNotifier();

  var candidates = <String>['model-a'];
  AppProviderConfig? lastProvider;
  String? lastProviderId;
  var refreshCalls = 0;

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;

  @override
  List<String> modelCandidates({
    required AppProviderConfig? provider,
    required String providerId,
    required String currentModel,
  }) =>
      candidates;

  @override
  Listenable get catalogUpdates => updates;

  @override
  bool isApplicable({required String model}) => true;

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) =>
      const ['low'];

  @override
  Future<void> refreshModelCatalog({
    required String providerId,
    AppProviderConfig? provider,
    String? executable,
    bool forceRefresh = false,
  }) async {
    refreshCalls++;
    lastProvider = provider;
    lastProviderId = providerId;
    candidates = ['model-a', 'model-b'];
    updates.notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDefinition implements CliToolDefinition {
  _FakeDefinition(this.capability);

  final ProviderCapability capability;

  @override
  CliTool get id => CliTool.claude;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [capability];
}

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

void main() {
  setUp(() {
    registerFallbackValue(CliTool.claude);
    setUpTestAppStorage();
  });
  tearDown(tearDownTestAppStorage);

  testWidgets('refresh helper forwards provider config to the capability', (
    tester,
  ) async {
    final capability = _FakeRefreshableCapability();
    var done = false;
    await tester.pumpWidget(
      CliToolRegistryScope(
        registry: CliToolRegistry()..register(_FakeDefinition(capability)),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                refreshComposeCascadeCatalog(
                  context,
                  cli: CliTool.claude,
                  providerId: 'prov-1',
                  provider: const AppProviderConfig(
                    id: 'prov-1',
                    cli: CliTool.claude,
                    name: 'Prov',
                    category: AppProviderCategory.official,
                  ),
                ).whenComplete(() => done = true);
              },
              child: const Text('run'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(capability.refreshCalls, 1);
    expect(capability.lastProviderId, 'prov-1');
    expect(capability.lastProvider?.id, 'prov-1');
    expect(capability.lastProvider?.category, AppProviderCategory.official);
  });

  testWidgets('open cascade menu live-updates after catalog refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final capability = _FakeRefreshableCapability();
    final workspace = Workspace(workspaceId: 'workspace-1', createdAt: 1);
    final chatCubit = _MockChatCubit();
    final appProviderCubit = _MockAppProviderCubit();
    final cliPresetsCubit = _MockCliPresetsCubit();
    final launchProfileCubit = _MockLaunchProfileCubit();
    final pluginCubit = _MockPluginCubit();
    final sessionPreferencesCubit = _MockSessionPreferencesCubit();
    final skillCubit = _MockSkillCubit();
    final worktreeCubit = _MockWorktreeCubit();

    _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
    _stubCubit(
      appProviderCubit,
      AppProviderState(providersByCli: {
        CliTool.claude: [
          const AppProviderConfig(
            id: 'deepseek-id',
            cli: CliTool.claude,
            name: 'DeepSeek',
          ),
        ],
      }),
    );
    _stubCubit(cliPresetsCubit, const CliPresetsState());
    _stubCubit(launchProfileCubit, const LaunchProfileState());
    _stubCubit(pluginCubit, const PluginState());
    _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
    when(() => sessionPreferencesCubit.resolveExecutable(any()))
        .thenReturn('claude');
    _stubCubit(skillCubit, const SkillState());
    _stubCubit(worktreeCubit, const WorktreeState());
    when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);

    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
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
            registry:
                CliToolRegistry()..register(_FakeDefinition(capability)),
            child: MaterialApp(
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: TpTheme(
                data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
                child: Scaffold(
                  body: WorkspaceChatLanding(
                    workspace: workspace,
                    onSubmit: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Open the auto chip menu → CLI group → provider → model submenu.
    await tester.tap(find.text('Use preset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('claude'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    expect(find.text('model-b'), findsNothing);

    // Opening the model submenu triggers refresh-on-open with the provider.
    await tester.tap(find.text('model-a'));
    await tester.pumpAndSettle();

    expect(capability.refreshCalls, 1);
    expect(capability.lastProviderId, 'deepseek-id');
    expect(capability.lastProvider?.id, 'deepseek-id');

    // Refresh landed while the menu stayed open: new candidate visible.
    expect(find.text('model-a'), findsOneWidget);
    expect(find.text('model-b'), findsOneWidget);
  });
}
