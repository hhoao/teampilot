import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/chat_page_shell.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/services/file_tree/workspace_file_tree_store.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';

import '../support/post_frame_test_harness.dart';

String _executable() => 'flashskyai';

class _ShellRebuildProbe extends StatefulWidget {
  const _ShellRebuildProbe({required this.child, super.key});

  final Widget child;

  @override
  State<_ShellRebuildProbe> createState() => _ShellRebuildProbeState();
}

class _ShellRebuildProbeState extends State<_ShellRebuildProbe> {
  int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return widget.child;
  }
}

void main() {
  setUp(() {
    setUpTestAppStorage();
  });

  tearDown(() {
    tearDownTestAppStorage();
  });

  testWidgets(
    'ChatPageShell does not rebuild when only workingSessionIds changes',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appData = Directory.systemTemp.createTempSync(
        'chat_rebuild_test_',
      );
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

      final probeKey = GlobalKey<_ShellRebuildProbeState>();

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
                BlocProvider.value(value: presenceCubit),
                BlocProvider.value(value: WorkspaceToolsCubit()),
              ],
              child: Scaffold(
                body: _ShellRebuildProbe(
                  key: probeKey,
                  child: const ChatPageShell(
                    cwd: '/tmp/personal-workspace',
                    isPersonalWorkspace: true,
                    workspaceId: 'personal-test',
                    team: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final countAfterSettle = probeKey.currentState!.buildCount;

      chatCubit.updateWorkingSessionsForTest({'sess-1'});
      await tester.pump();

      expect(probeKey.currentState!.buildCount, countAfterSettle);
    },
  );
}
