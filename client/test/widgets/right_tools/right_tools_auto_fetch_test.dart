import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/file_tree/workspace_file_tree_store.dart';
import 'package:teampilot/services/git/git_history_actions.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/right_tools/right_tools_lifecycle.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_preferences.dart';

import '../../support/post_frame_test_harness.dart';
import '../../support/test_runtime_context.dart';

class _EmptyGitStub extends GitService {
  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async =>
      const GitRepoStatus(isRepository: false, hasCommits: false);
}

class _RecordingActions extends GitHistoryActions {
  _RecordingActions(this.fetchedRoots);

  final List<String> fetchedRoots;

  @override
  Future<void> fetchAllQuiet(String dir) async => fetchedRoots.add(dir);
}

void main() {
  late GitRepoStore store;
  late WorkspaceFileTreeStore fileTreeStore;
  late SessionPreferencesCubit prefsCubit;
  late List<String> fetchedRoots;
  // Captured from the mounted host; owned (and disposed) by the host itself.
  late ValueNotifier<String?> selectedRoot;

  setUp(() async {
    setUpTestAppStorage();
    GitService.debugOverrideFactory = _EmptyGitStub.new;
    GitService.debugResetExecutableCache();
    store = GitRepoStore();
    fileTreeStore = WorkspaceFileTreeStore();
    fetchedRoots = [];
    GitHistoryActions.debugOverrideFactory = () =>
        _RecordingActions(fetchedRoots);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    prefsCubit = SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
    );
    await prefsCubit.load();
  });

  tearDown(() async {
    GitService.debugOverrideFactory = null;
    GitService.debugResetExecutableCache();
    GitHistoryActions.debugOverrideFactory = null;
    await prefsCubit.close();
    store.dispose();
    fileTreeStore.removeWorkspace('ws-test');
    tearDownTestAppStorage();
  });

  Future<void> pumpHost(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        home: WorkspaceToolsScope(
          state: WorkspaceToolsScopeState(
            tools: WorkspaceToolsContext(
              targetId: 'test',
              context: testRuntimeContext('/home'),
            ),
            roots: const ['/home/repoA', '/home/repoB'],
            resolving: false,
          ),
          child: BlocProvider<SessionPreferencesCubit>.value(
            value: prefsCubit,
            child: RepositoryProvider<GitRepoStore>.value(
              value: store,
              child: RepositoryProvider<WorkspaceFileTreeStore>.value(
                value: fileTreeStore,
                child: RightToolsLifecycleHost(
                  cwd: '/home/repoA',
                  additionalPaths: const ['/home/repoB'],
                  workspaceId: 'ws-test',
                  preferences: const RightToolsToolPreferences(
                    fileTreeVisible: false,
                    gitVisible: true,
                    searchVisible: false,
                    membersVisible: false,
                    boardVisible: false,
                  ),
                  child: Builder(
                    builder: (context) {
                      selectedRoot = RightToolsLifecycle.of(
                        context,
                      ).selectedGitRoot;
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The host's activation → scope sync → staggered disk-refresh chain is
  /// chained post-frame callbacks that do not themselves schedule frames, so
  /// neither [WidgetTester.pumpAndSettle] nor bare [WidgetTester.pump] advance
  /// it — schedule a frame before each pump.
  Future<void> pumpLifecycleFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }
  }

  testWidgets('fetches first root on activation, follows selection, '
      'stops when disabled', (tester) async {
    await pumpHost(tester);
    await pumpLifecycleFrames(tester);

    expect(fetchedRoots, [
      '/home/repoA',
    ], reason: 'immediate fetch of first root once the panel warms up');

    selectedRoot.value = '/home/repoB';
    await tester.pump();
    expect(
      fetchedRoots.last,
      '/home/repoB',
      reason: 'selection change retargets with an immediate fetch',
    );

    await prefsCubit.setGitAutoFetchEnabled(false);
    await tester.pump();
    final countAfterDisable = fetchedRoots.length;

    selectedRoot.value = '/home/repoA';
    await tester.pump();
    expect(
      fetchedRoots.length,
      countAfterDisable,
      reason: 'no fetch while the setting is off',
    );
  });

  testWidgets('no fetch when git tool is hidden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceToolsScope(
          state: WorkspaceToolsScopeState(
            tools: WorkspaceToolsContext(
              targetId: 'test',
              context: testRuntimeContext('/home'),
            ),
            roots: const ['/home/repoA'],
            resolving: false,
          ),
          child: BlocProvider<SessionPreferencesCubit>.value(
            value: prefsCubit,
            child: RepositoryProvider<GitRepoStore>.value(
              value: store,
              child: RepositoryProvider<WorkspaceFileTreeStore>.value(
                value: fileTreeStore,
                child: RightToolsLifecycleHost(
                  cwd: '/home/repoA',
                  additionalPaths: const [],
                  workspaceId: 'ws-test',
                  preferences: const RightToolsToolPreferences(
                    fileTreeVisible: true,
                    gitVisible: false,
                    searchVisible: false,
                    membersVisible: false,
                    boardVisible: false,
                  ),
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await pumpLifecycleFrames(tester);
    expect(fetchedRoots, isEmpty);
  });
}
