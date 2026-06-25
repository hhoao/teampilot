import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/config/member_folder_assignment_tile.dart';
import 'package:teampilot/pages/home_workspace/workspace/member_folder_assignment_dialog.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

/// Reachability: the chat-workbench member panel opens this dialog with a real
/// session+repo; the assignment tile renders and selecting a target persists via
/// SessionRepository.setMemberTarget (guards against an orphan UI).
void main() {
  testWidgets('dialog renders the tile and persists a target selection',
      (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('assign_dialog_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final fs = LocalFilesystem();
      final repo = SessionRepository(rootDir: tmp.path);

      // Workspace with two targets; session inherits its folders.
      await repo.createWorkspace([WorkspaceFolder(path: '/local-proj')]);
      final ws = (await repo.loadWorkspaces()).single;
      await repo.updateWorkspaceFolders(ws.workspaceId, [
        const WorkspaceFolder(path: '/local-proj'),
        const WorkspaceFolder(path: '/remote-proj', targetId: 'ssh:p1'),
      ]);
      final session = await repo.createSession(ws.workspaceId);

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

      await tester.pumpWidget(
        // Provider above MaterialApp — mirrors main.dart, where dialogs opened on
        // the root navigator can still read it.
        RepositoryProvider<HomeTargetController>.value(
          value: controller,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showMemberFolderAssignmentDialog(
                      context,
                      repository: repo,
                      sessionId: session.sessionId,
                      memberId: 'm1',
                      memberLabel: 'developer',
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump(); // build dialog; initState kicks off the async load
      // The dialog loads async (session + selectable targets). Let the real file
      // IO settle (we're inside runAsync), then rebuild.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump();

      // The assignment tile is reachable inside the dialog.
      expect(find.byType(MemberFolderAssignmentTile), findsOneWidget);

      // Select the ssh target → its folders get persisted.
      await tester.tap(find.text('/remote-proj'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();

      final reloaded = (await repo.loadSessions())
          .firstWhere((s) => s.sessionId == session.sessionId);
      expect(reloaded.memberTargets['m1'], 'ssh:p1');
    });
  });
}
