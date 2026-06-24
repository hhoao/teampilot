import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/config/member_folder_assignment_tile.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

void main() {
  testWidgets('selecting a target assigns that target\'s folders', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('member_assign_');
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
      final workspace = Workspace(
        workspaceId: 'w1',
        folders: const [
          WorkspaceFolder(path: '/local-proj'),
          WorkspaceFolder(path: '/remote-proj', targetId: 'ssh:p1'),
        ],
        createdAt: 1,
      );
      final assigned = <List<String>>[];
      var current = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RepositoryProvider<HomeTargetController>.value(
            value: controller,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => MemberFolderAssignmentTile(
                  memberLabel: 'developer',
                  workspace: workspace,
                  currentAssignment: current,
                  onAssign: (paths) {
                    assigned.add(paths);
                    setState(() => current = paths);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      // Selecting the ssh target row assigns the ssh folder path.
      await tester.tap(find.text('/remote-proj'));
      await tester.pump();
      expect(assigned.last, ['/remote-proj']);

      // The inherit row assigns an empty list.
      await tester.tap(find.text('Inherit workspace folders'));
      await tester.pump();
      expect(assigned.last, isEmpty);
    });
  });
}
