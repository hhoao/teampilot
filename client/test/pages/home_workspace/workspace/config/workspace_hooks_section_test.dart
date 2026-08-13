import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/hook_cubit.dart';
import 'package:teampilot/cubits/workspace_project_config_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/pages/home_workspace/workspace/config/workspace_hooks_section.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import '../../../../support/in_memory_filesystem.dart';

void main() {
  testWidgets('workspace hooks section lists library and toggles assignment', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    final hookRepository = HookRepository(fs: fs, teampilotRoot: '/root');
    await hookRepository.save(const HookDefinition(
      id: 'h1',
      name: 'On start',
      event: HookEvent.sessionStart,
      action: CommandHookAction.raw('echo a'),
    ));
    final hookCubit = HookCubit(repository: hookRepository)..load();
    addTearDown(hookCubit.close);

    final projectRepository = WorkspaceProjectConfigRepository(
      fs: fs,
      layout: WorkspaceLayout(teampilotRoot: '/root', fs: fs),
    );
    final projectCubit = WorkspaceProjectConfigCubit(
      repository: projectRepository,
      workspaceId: 'ws1',
    )..load();
    addTearDown(projectCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<HookCubit>.value(value: hookCubit),
          BlocProvider<WorkspaceProjectConfigCubit>.value(
            value: projectCubit,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: WorkspaceHooksSection(workspaceId: 'ws1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('On start'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(projectCubit.state.config.bundle.hookIds, contains('h1'));
  });
}
