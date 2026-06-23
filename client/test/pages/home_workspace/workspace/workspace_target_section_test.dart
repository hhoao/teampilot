import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/config/workspace_target_section.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

void main() {
  testWidgets('lists targets and selecting one stamps the workspace target',
      (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('ws_target_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final fs = LocalFilesystem();

      // Seed an ssh profile so the registry offers ssh:p1.
      await SshProfileRepository(rootDir: tmp.path, fs: fs).save(
        const SshProfile(id: 'p1', name: 'box', host: 'h', username: 'u'),
      );
      final registry = RuntimeTargetRegistry(
        repo: TargetsRepository(rootDir: tmp.path, fs: fs),
        sshProfileRepo: SshProfileRepository(rootDir: tmp.path, fs: fs),
        isWindows: false,
        isAndroid: false,
      );
      final controller = HomeTargetController(
        registry: registry,
        current: RuntimeTarget.local,
        switchTo: (_) async {},
      );

      final repo = SessionRepository(rootDir: tmp.path);
      final ws = await repo.createWorkspace('/proj');
      final chat = ChatCubit(executableResolver: () => 'flashskyai');
      addTearDown(chat.close);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<HomeTargetController>.value(value: controller),
              RepositoryProvider<SessionRepository>.value(value: repo),
            ],
            child: BlocProvider<ChatCubit>.value(
              value: chat,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: WorkspaceTargetSection(workspace: ws),
                ),
              ),
            ),
          ),
        ),
      );
      // Let the listSelectable future resolve (avoid pumpAndSettle — the
      // loading LinearProgressIndicator animates forever).
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      // local + ssh:p1 are offered; local is current.
      expect(find.text('ssh:p1'), findsOneWidget);

      await tester.tap(find.text('box'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();

      final reloaded = (await repo.loadWorkspaces()).single;
      expect(reloaded.folders.first.targetId, 'ssh:p1');
    });
  });
}
