import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/hook_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/pages/team_config/team_config_hooks_section.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  testWidgets('team hooks section lists library and toggles assignment', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    final repository = HookRepository(fs: fs, teampilotRoot: '/root');
    await repository.save(const HookDefinition(
      id: 'h1',
      name: 'On start',
      event: HookEvent.sessionStart,
      action: CommandHookAction.raw('echo a'),
    ));
    final hookCubit = HookCubit(repository: repository)..load();
    addTearDown(hookCubit.close);

    var teamHookIds = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: BlocProvider<HookCubit>.value(
            value: hookCubit,
            child: TeamHooksSection(
              assignedIds: teamHookIds,
              onAssignedChanged: (ids) => teamHookIds = ids,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('On start'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(teamHookIds, contains('h1'));
  });
}
