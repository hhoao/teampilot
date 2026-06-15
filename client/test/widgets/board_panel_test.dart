import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/board_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/widgets/right_tools/board_panel.dart';

TeamTask _task(String id, int seq, TaskStatus s, {String? assignee}) =>
    TeamTask(
      id: id,
      seq: seq,
      title: 'Task $seq',
      brief: '',
      createdBy: 'team-lead',
      createdAt: 0,
      status: s,
      assignee: assignee,
    );

/// Stub bus for widget testing — BoardCubit reads listTasks.
class _StubBus implements TeamBus {
  _StubBus(this._tasks);
  final List<TeamTask> _tasks;

  @override
  List<TeamTask> listTasks({TaskStatus? status}) {
    if (status == null) return List.unmodifiable(_tasks);
    return _tasks.where((t) => t.status == status).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('StubBus: ${invocation.memberName}');
}

Widget _host({required Widget child, required BoardCubit boardCubit}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: BlocProvider.value(value: boardCubit, child: child),
    ),
  );
}

void main() {
  testWidgets('renders columns and assignee chip', (tester) async {
    // Bus returns tasks that BoardCubit buckets naturally.
    final bus = _StubBus([
      _task('a', 1, TaskStatus.pending),
      _task('b', 2, TaskStatus.claimed, assignee: 'developer'),
    ]);
    final boardCubit = BoardCubit(
      activeBus: () => bus,
      pollInterval: const Duration(minutes: 1),
    );

    final team = TeamConfig(
      id: 't1',
      name: 'Team',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
      members: [
        TeamMemberConfig(id: 'developer', name: 'Dev'),
      ],
    );

    await tester.pumpWidget(_host(
      boardCubit: boardCubit,
      child: BoardPanel(team: team, cwd: '/proj'),
    ));
    await tester.pump();

    expect(find.text('Task 1'), findsOneWidget);
    expect(find.text('Task 2'), findsOneWidget);
    expect(find.text('› Dev'), findsOneWidget); // resolved assignee chip
    expect(find.text('Pending'), findsOneWidget); // column header
    expect(find.text('In progress'), findsOneWidget); // column header

    addTearDown(() => boardCubit.close());
  });

  testWidgets('shows empty state when no tasks', (tester) async {
    final bus = _StubBus([]);
    final boardCubit = BoardCubit(
      activeBus: () => bus,
      pollInterval: const Duration(minutes: 1),
    );

    await tester.pumpWidget(_host(
      boardCubit: boardCubit,
      child: BoardPanel(
        team: TeamConfig(
          id: 't1', name: 'Team', cli: CliTool.claude,
          teamMode: TeamMode.mixed, members: const [],
        ),
        cwd: '/proj',
      ),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.view_kanban_outlined), findsOneWidget);

    addTearDown(() => boardCubit.close());
  });
}
