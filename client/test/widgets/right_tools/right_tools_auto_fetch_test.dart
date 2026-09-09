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

  Future<void> pumpHost(
    WidgetTester tester, {
    bool fileTreeVisible = false,
    bool gitVisible = true,
    bool tickerEnabled = true,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: tickerEnabled,
          child: WorkspaceToolsScope(
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
                    preferences: RightToolsToolPreferences(
                      fileTreeVisible: fileTreeVisible,
                      gitVisible: gitVisible,
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
    await pumpHost(tester, fileTreeVisible: true, gitVisible: false);
    await pumpLifecycleFrames(tester);
    expect(fetchedRoots, isEmpty);
  });

  // Regression: _setupDiskRefresh early-returns when no tool needs disk side
  // effects (git + file tree both hidden, host kept alive by another tool) —
  // the running scheduler must be stopped on that path too, not only when
  // needsDiskSideEffects stays true.
  testWidgets('stops fetching when git tool is hidden while the file tree '
      'is hidden too', (tester) async {
    await pumpHost(tester, fileTreeVisible: false, gitVisible: true);
    await pumpLifecycleFrames(tester);
    expect(fetchedRoots, ['/home/repoA']);

    // Hide the git tab via didUpdateWidget; fileTreeVisible stays false, so
    // needsDiskSideEffects is false and the early return path is taken.
    await pumpHost(tester, fileTreeVisible: false, gitVisible: false);
    expect(fetchedRoots, [
      '/home/repoA',
    ], reason: 'hiding git must not trigger an extra immediate fetch');

    // Advance past one default interval (5 min) — a leaked scheduler would
    // have fired here.
    await tester.pump(const Duration(minutes: 6));
    expect(fetchedRoots, [
      '/home/repoA',
    ], reason: 'no interval fetch after the git tool is hidden');
  });

  // Regression: a session-prefs emission (interval change from the settings
  // UI) arriving while the host is backgrounded must not (re)start the
  // scheduler — auto-fetch stays gated on foreground activity.
  testWidgets('interval change while backgrounded does not start fetching', (
    tester,
  ) async {
    await pumpHost(tester);
    await pumpLifecycleFrames(tester);
    expect(fetchedRoots, ['/home/repoA']);

    // Background the host (keep-alive tab switch): TickerMode off triggers
    // didChangeDependencies → suspend path.
    await pumpHost(tester, tickerEnabled: false);
    await pumpLifecycleFrames(tester);
    expect(fetchedRoots, [
      '/home/repoA',
    ], reason: 'backgrounding must not trigger a fetch');

    await prefsCubit.setGitAutoFetchIntervalMinutes(1);
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    expect(
      fetchedRoots,
      ['/home/repoA'],
      reason:
          'no fetch from a prefs emission while backgrounded, neither '
          'immediately nor on the new interval',
    );
  });
}
