import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/board_column.dart';
import '../services/team_bus/tasks/team_task.dart';
import '../services/team_bus/team_bus.dart';
import 'scoped_bus_poll_gate.dart';

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

/// Read-only poll of a workspace-tab-scoped [TeamBus] task queue. Mixed-mode
/// only — native mode has no task queue and the panel is gated out of the views
/// list before attach.
class BoardCubit extends Cubit<BoardState> {
  BoardCubit({
    required TeamBus? Function(String tabScopeId) busForScope,
    Duration pollInterval = const Duration(milliseconds: 1500),
  }) : super(const BoardState()) {
    _poll = ScopedBusPollGate(
      busForScope: busForScope,
      pollInterval: pollInterval,
      onTick: _pollBus,
    );
  }

  late final ScopedBusPollGate _poll;

  void attachUi(String tabScopeId, [Object? owner]) =>
      _poll.attachUi(tabScopeId, owner);

  void detachUi([Object? owner]) => _poll.detachUi(owner);

  Future<void> _pollBus(TeamBus? bus) async {
    if (isClosed) return;
    if (bus == null) {
      if (state != BoardState.empty) emit(BoardState.empty);
      return;
    }
    if (!_poll.isAttached) return;
    emit(_bucket(bus.listTasks()));
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
    _poll.dispose();
    return super.close();
  }
}
