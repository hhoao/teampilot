import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
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

/// Reachability guard: the workspace folders editor is rendered by the *live*
/// workspace-settings body (WorkspaceInfoSection) — not an orphan view.
void main() {
  testWidgets('WorkspaceInfoSection shows the workspace folders editor',
      (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('ws_info_target_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final fs = LocalFilesystem();
      final controller = HomeTargetController(
        registry: RuntimeTargetRegistry(
          repo: TargetsRepository(rootDir: tmp.path, fs: fs),
          sshProfileRepo: SshProfileRepository(rootDir: tmp.path, fs: fs),
          isWindows: false,
          isAndroid: false,
        ),
        current: RuntimeTarget.local,
        switchTo: (_) async {},
      );
      final chat = ChatCubit(executableResolver: () => 'flashskyai');
      addTearDown(chat.close);
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
              RepositoryProvider<SessionRepository>.value(
                value: SessionRepository(rootDir: tmp.path),
              ),
            ],
            child: BlocProvider<ChatCubit>.value(
              value: chat,
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
