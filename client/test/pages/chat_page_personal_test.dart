import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/identity_cubit.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat_page.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/identity_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';

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

    final teamCubit = IdentityCubit(
      repository: IdentityRepository(rootDir: appData.path),
      sessionRepository: SessionRepository(rootDir: appData.path),
      reloadProjects: () async {},
      executableResolver: _executable,
      appDataBasePath: appData.path,
      configProfileService: ConfigProfileService(basePath: appData.path),
    );
    addTearDown(() => teamCubit.close());

    final sessionRepo = SessionRepository(rootDir: appData.path);
    final chatCubit = ChatCubit(
      executableResolver: _executable,
      sessionRepository: sessionRepo,
    );
    addTearDown(() => chatCubit.close());

    final layoutCubit = LayoutCubit();
    addTearDown(() => layoutCubit.close());

    final editorCubit = EditorCubit(fs: LocalFilesystem());
    addTearDown(() => editorCubit.close());

    final presenceCubit = MemberPresenceCubit();
    chatCubit.bindPresenceCubit(presenceCubit);
    addTearDown(() => presenceCubit.close());

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepositoryProvider<SessionRepository>.value(
          value: sessionRepo,
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: teamCubit),
              BlocProvider.value(value: chatCubit),
              BlocProvider.value(value: layoutCubit),
              BlocProvider.value(value: editorCubit),
              BlocProvider.value(value: presenceCubit),
              BlocProvider.value(value: WorkspaceToolsCubit()),
            ],
            child: const Scaffold(
              body: ChatPage(
                cwd: '/tmp/personal-project',
                isPersonalProject: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(teamCubit.state.selectedTeam, isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(WorkspaceShell), findsOneWidget);
  });
}
