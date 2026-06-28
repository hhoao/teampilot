import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/config/workspace_folders_section.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';

import '../../../support/test_home_target_controller.dart';

void main() {
  testWidgets('WorkspaceFoldersSection renders folder rows with target catalog',
      (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('ws_folders_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/proj'),
      ]);
      final chat = ChatCubit(executableResolver: () => 'flashskyai');
      addTearDown(chat.close);
      chat.ingestWorkspaceSessionSnapshot(workspaces: [ws], sessions: const []);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<HomeTargetController>.value(
                value: testHomeTargetController(),
              ),
              RepositoryProvider<SessionRepository>.value(value: repo),
            ],
            child: BlocProvider<ChatCubit>.value(
              value: chat,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: WorkspaceFoldersSection(workspace: ws),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.workspaceFoldersSectionTitle), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(find.text(l10n.addWorkspaceDirectory), findsOneWidget);
    });
  });
}
