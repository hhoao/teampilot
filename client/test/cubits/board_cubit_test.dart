import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/board_cubit.dart';
import 'package:teampilot/models/board_column.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

/// Minimal double exposing only listTasks(), which is all BoardCubit reads.
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

void main() {
  group('BoardCubit', () {
    test('emits empty state when bus is null', () async {
      final cubit = BoardCubit(activeBus: () => null);
      cubit.attach();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.total, 0);
      expect(cubit.state.columns[BoardColumn.pending], isNull);
      cubit.detach();
      await cubit.close();
    });

    test('buckets tasks by status on attach', () async {
      final bus = _StubBus([
        _task('a', 1, TaskStatus.pending),
        _task('b', 2, TaskStatus.claimed, assignee: 'developer'),
        _task('c', 3, TaskStatus.done, assignee: 'reviewer'),
        _task('d', 4, TaskStatus.failed, assignee: 'reviewer'),
      ]);
      final cubit = BoardCubit(
        activeBus: () => bus,
        pollInterval: const Duration(milliseconds: 10),
      );
      cubit.attach();
      // Allow the immediate _tick() to run.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cubit.state.total, 4);
      expect(cubit.state.columns[BoardColumn.pending]!.length, 1);
      expect(cubit.state.columns[BoardColumn.claimed]!.length, 1);
      expect(cubit.state.columns[BoardColumn.done]!.length, 2);
      // seq preserved within a column
      expect(cubit.state.columns[BoardColumn.pending]!.first.seq, 1);
      expect(cubit.state.columns[BoardColumn.done]!.first.seq, 3);

      cubit.detach();
      await cubit.close();
    });

    test('detach clears state to empty', () async {
      final bus = _StubBus([_task('a', 1, TaskStatus.pending)]);
      final cubit = BoardCubit(activeBus: () => bus);
      cubit.attach();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cubit.state.total, 1);

      cubit.detach();
      expect(cubit.state.total, 0);
      expect(cubit.state.columns, isEmpty);
      await cubit.close();
    });
  });
}
