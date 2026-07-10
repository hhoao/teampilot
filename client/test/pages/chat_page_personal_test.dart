import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/cubits/workspace_landing_context_cubit.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat_page.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/services/file_tree/workspace_file_tree_store.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/plugin/plugin_repo_service.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';

import '../support/in_memory_filesystem.dart';
import '../support/post_frame_test_harness.dart';

String _executable() => 'flashskyai';

void main() {
  setUp(() {
    setUpTestAppStorage();
  });

  tearDown(() {
    tearDownTestAppStorage();
  });

  testWidgets('ChatPage personal mode builds without selected team', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final appData = Directory.systemTemp.createTempSync('chat_personal_test_');
    addTearDown(() {
      if (appData.existsSync()) appData.deleteSync(recursive: true);
    });

    final teamCubit = LaunchProfileCubit(
      repository: LaunchProfileRepository(rootDir: appData.path),
      sessionRepository: SessionRepository(rootDir: appData.path),
      executableResolver: _executable,
      appDataBasePath: appData.path,
      configProfileService: ConfigProfileService(basePath: appData.path),
    );
    addTearDown(() => teamCubit.close());

    await tester.runAsync(() => teamCubit.load());

    final sessionRepo = SessionRepository(rootDir: appData.path);
    final chatCubit = ChatCubit(
      executableResolver: _executable,
      automationRepository: testAutomationRepository(),
      sessionRepository: sessionRepo,
    );
    addTearDown(() => chatCubit.close());

    final layoutCubit = LayoutCubit();
    addTearDown(() => layoutCubit.close());

    final editorCubit = EditorCubit(fs: LocalFilesystem());
    addTearDown(() => editorCubit.close());

    final workbenchCubit = WorkbenchCubit();
    addTearDown(() => workbenchCubit.close());

    final skillCubit = SkillCubit(SkillRepository());
    addTearDown(() => skillCubit.close());

    final pluginRepo = PluginRepository();
    final pluginCubit = PluginCubit(
      repository: pluginRepo,
      installService: pluginRepo.install,
      repoService: PluginRepoService(),
    );
    addTearDown(() => pluginCubit.close());

    final worktreeCubit = WorktreeCubit();
    addTearDown(() => worktreeCubit.close());

    final presenceCubit = MemberPresenceCubit();
    chatCubit.bindPresenceCubit(presenceCubit);
    addTearDown(() => presenceCubit.close());

    final cliPresetsCubit = CliPresetsCubit(
      repository: CliPresetsRepository(
        fs: InMemoryFilesystem(),
        presetsPath: '/cli-presets.json',
      ),
    );
    cliPresetsCubit.emit(
      const CliPresetsState(status: CliPresetsLoadStatus.ready),
    );
    addTearDown(() => cliPresetsCubit.close());

    chatCubit.ingestWorkspaceSessionSnapshot(
      workspaces: [
        Workspace(
          workspaceId: 'personal-test',
          folders: [WorkspaceFolder(path: '/tmp/personal-workspace')],
          createdAt: 1,
        ),
      ],
      sessions: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<GitRepoStore>(create: (_) => GitRepoStore()),
            RepositoryProvider<WorkspaceFileTreeStore>(
              create: (_) => WorkspaceFileTreeStore(),
            ),
            RepositoryProvider<SessionRepository>.value(value: sessionRepo),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: teamCubit),
              BlocProvider.value(value: chatCubit),
              BlocProvider.value(value: layoutCubit),
              BlocProvider.value(value: editorCubit),
              BlocProvider.value(value: workbenchCubit),
              BlocProvider.value(value: skillCubit),
              BlocProvider.value(value: pluginCubit),
              BlocProvider.value(value: worktreeCubit),
              BlocProvider.value(value: presenceCubit),
              BlocProvider.value(value: WorkspaceToolsCubit()),
              BlocProvider.value(value: cliPresetsCubit),
              BlocProvider(
                create: (_) => WorkspaceLandingContextCubit(
                  workspaceId: 'personal-test',
                  initial: const LandingLaunchContext(isPersonal: true),
                ),
              ),
            ],
            child: WorkspaceToolsScope(
              state: const WorkspaceToolsScopeState(resolving: false),
              child: Scaffold(
                body: ChatPage(
                  cwd: '/tmp/personal-workspace',
                  workspaceId: 'personal-test',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(teamCubit.state.isLoading, isFalse);
    expect(find.byType(WorkspaceShell), findsOneWidget);
  });
}
