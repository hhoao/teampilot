import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_config_section.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_config_workspace.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/widgets/settings/workspace_hub_shell.dart';
import 'package:teampilot/widgets/settings/workspace_pane_insets.dart';
import 'package:teampilot/widgets/settings/workspace_section_tab_bar.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late SkillCubit skillCubit;

  setUp(() {
    setUpTestAppStorage();
    skillCubit = testSkillCubit();
  });

  tearDown(() async {
    if (!skillCubit.isClosed) await skillCubit.close();
    tearDownTestAppStorage();
  });

  testWidgets('narrow shows compact manage section tabs', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final workspace = Workspace(workspaceId: 'ws-1', createdAt: 1);
    final theme = ThemeData(useMaterial3: true);

    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme,
          home: Scaffold(
            body: RepositoryProvider(
              create: (_) => WorkspaceProjectConfigRepository(),
              child: BlocProvider<SkillCubit>.value(
                value: skillCubit,
                child: SizedBox(
                  width: 400,
                  height: 800,
                  child: WorkspaceConfigPanel(
                    workspace: workspace,
                    section: WorkspaceConfigSection.skills,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Workspace settings'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Plugins'), findsOneWidget);
    expect(find.text('MCP'), findsOneWidget);
    expect(find.text('Extensions'), findsOneWidget);
    expect(find.byType(WorkspaceSectionTabBar), findsOneWidget);
    expect(find.byType(WorkspaceSplitShell), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Padding && widget.padding == WorkspacePaneInsets.page,
      ),
      findsOneWidget,
    );
  });
}
