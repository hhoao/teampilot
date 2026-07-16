import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_info_section.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';
import '../../../support/post_frame_test_harness.dart';

/// Reachability guard: the workspace folders editor is rendered by the *live*
/// workspace-settings body (WorkspaceInfoSection) — not an orphan view.
void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('WorkspaceInfoSection shows the workspace folders editor', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('ws_info_target_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final fs = LocalFilesystem();
      final sshRepo = SshProfileRepository(rootDir: tmp.path, fs: fs);
      final controller = HomeTargetController(
        registry: RuntimeTargetRegistry(
          repo: TargetsRepository(rootDir: tmp.path, fs: fs),
          sshProfileRepo: sshRepo,
          isWindows: false,
          isAndroid: false,
        ),
        current: RuntimeTarget.local,
        switchTo: (_) async {},
      );
      final chat = ChatCubit(
        executableResolver: () => 'flashskyai',
        automationRepository: testAutomationRepository(),
      );
      addTearDown(chat.close);
      final launchProfiles = LaunchProfileCubit(
        repository: testLaunchProfileRepository(tmp),
        sessionRepository: SessionRepository(rootDir: tmp.path),
        executableResolver: () => 'claude',
      );
      addTearDown(launchProfiles.close);
      final ws = Workspace(
        workspaceId: 'w1',
        folders: const [WorkspaceFolder(path: '/proj')],
        createdAt: 1,
      );
      chat.ingestWorkspaceSessionSnapshot(workspaces: [ws], sessions: const []);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<HomeTargetController>.value(value: controller),
              RepositoryProvider<SshProfileRepository>.value(value: sshRepo),
              RepositoryProvider<SessionRepository>.value(
                value: SessionRepository(rootDir: tmp.path),
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>.value(value: chat),
                BlocProvider<LaunchProfileCubit>.value(value: launchProfiles),
              ],
              child: Scaffold(body: WorkspaceInfoSection(workspace: ws)),
            ),
          ),
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.workspaceFoldersSectionTitle), findsOneWidget);
    });
  });
}
