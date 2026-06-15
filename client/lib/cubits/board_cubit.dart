import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/board_column.dart';
import '../services/team_bus/tasks/team_task.dart';
import '../services/team_bus/team_bus.dart';

/// Immutable projection of a [TeamTask] for display. Derived per tick; never
/// persisted. Kept as a separate type so the UI doesn't depend on fields it
/// doesn't render (brief, dependsOn, timestamps).
class BoardCard extends Equatable {
  const BoardCard({
    required this.id,
    required this.seq,
    required this.title,
    required this.status,
    required this.column,
    this.assigneeId,
  });

  final String id;
  final int seq;
  final String title;
  final TaskStatus status;
  final BoardColumn column;

  /// Raw memberId; BoardPanel resolves to a display name. Null when pending.
  final String? assigneeId;

  @override
  List<Object?> get props => [id, seq, title, status, column, assigneeId];
}

class BoardState extends Equatable {
  const BoardState({
    Map<BoardColumn, List<BoardCard>>? columns,
    this.total = 0,
  }) : columns = columns ?? const {};

  final Map<BoardColumn, List<BoardCard>> columns;
  final int total;

  static const empty = BoardState();

  @override
  List<Object?> get props => [columns, total];
}

/// Read-only poll of the active tab's [TeamBus] task queue. Isomorphic to
/// [MailboxCubit]: attach()/detach() gate a periodic timer; each tick reads
/// the synchronous [TeamBus.listTasks] and buckets into [BoardState].
///
/// Mixed-mode only — in native mode the bus's task queue is null and
/// listTasks() returns an empty list, but the panel is gated out of the
/// views list before this cubit is ever attached (see RightToolsPanel).
class BoardCubit extends Cubit<BoardState> {
  BoardCubit({
    required TeamBus? Function() activeBus,
    Duration pollInterval = const Duration(milliseconds: 1500),
  })  : _activeBus = activeBus,
        _pollInterval = pollInterval,
        super(const BoardState());

  final TeamBus? Function() _activeBus;
  final Duration _pollInterval;
  Timer? _timer;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    _timer?.cancel();
    unawaited(_tick());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _timer?.cancel();
    _timer = null;
    if (state != BoardState.empty) emit(BoardState.empty);
  }

  Future<void> _tick() async {
    if (!_attached || isClosed) return;
    final bus = _activeBus();
    if (bus == null) {
      if (state != BoardState.empty) emit(BoardState.empty);
      return;
    }
    final tasks = bus.listTasks();
    if (!_attached || isClosed) return;
    emit(_bucket(tasks));
  }

  BoardState _bucket(List<TeamTask> tasks) {
    final columns = <BoardColumn, List<BoardCard>>{
      for (final c in BoardColumn.values) c: <BoardCard>[],
    };
    for (final t in tasks) {
      final column = BoardColumnMapping.forStatus(t.status);
      columns[column]!.add(BoardCard(
        id: t.id,
        seq: t.seq,
        title: t.title,
        status: t.status,
        column: column,
        assigneeId: t.assignee,
      ));
    }
    return BoardState(columns: columns, total: tasks.length);
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
