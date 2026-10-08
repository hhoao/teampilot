import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/right_tools/right_tool_ids.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_preferences.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_views.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

const _team = TeamProfile(
  id: 'team-1',
  name: 'Team',
  members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
);

const _prefs = RightToolsToolPreferences(
  fileTreeVisible: true,
  gitVisible: true,
  searchVisible: false,
  membersVisible: true,
  boardVisible: false,
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('team context seeds members after a post-frame callback', (
    tester,
  ) async {
    final tools = await _pumpToolViews(
      tester,
      isPersonalContext: false,
      team: _team,
    );

    expect(tools.openIdsFor('ws-1'), contains(RightToolIds.members));
  });

  testWidgets('personal context does not seed members', (tester) async {
    final tools = await _pumpToolViews(
      tester,
      isPersonalContext: true,
      team: null,
    );

    expect(tools.openIdsFor('ws-1'), isNot(contains(RightToolIds.members)));
  });
}

Future<WorkspaceToolsCubit> _pumpToolViews(
  WidgetTester tester, {
  required bool isPersonalContext,
  required TeamProfile? team,
}) async {
  final toolsCubit = WorkspaceToolsCubit();
  final workbench = WorkbenchCubit();
  final chat = testChatCubit(executableResolver: () => '/bin/true');
  final fileTree = FileTreeCubit(fs: InMemoryFilesystem());
  final providers = AppProviderCubit(storage: testHomeStorage);
  final presets = CliPresetsCubit(
    repository: CliPresetsRepository(
      fs: InMemoryFilesystem(),
      presetsPath: '/cli-presets.json',
    ),
  );
  final searchFocus = ValueNotifier<int>(0);
  addTearDown(() async {
    searchFocus.dispose();
    await toolsCubit.close();
    await workbench.close();
    await chat.close();
    await fileTree.close();
    await providers.close();
    await presets.close();
  });

  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB));
  await tester.pumpWidget(
    TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
      child: MaterialApp(
        theme: ThemeData(colorScheme: scheme, useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: toolsCubit),
              BlocProvider.value(value: workbench),
              BlocProvider<ChatCubit>.value(value: chat),
              BlocProvider.value(value: providers),
              BlocProvider.value(value: presets),
            ],
            child: RightToolsToolViews(
              preferences: _prefs,
              cwd: '/ws',
              workspaceId: 'ws-1',
              toolsScopeId: 'ws-1',
              isPersonalContext: isPersonalContext,
              team: team,
              dismissDrawerOnAction: false,
              fileTreeCubit: fileTree,
              workContext: testHomeStorage.context,
              scope: const WorkspaceToolsScopeState(resolving: false),
              searchFocusRequest: searchFocus,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return toolsCubit;
}
