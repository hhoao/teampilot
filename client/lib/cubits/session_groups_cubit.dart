import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/session_group.dart';
import '../repositories/session_group_repository.dart';

enum SessionGroupsStatus { loading, ready }

class SessionGroupsState {
  const SessionGroupsState({
    this.status = SessionGroupsStatus.loading,
    this.workspaceId = '',
    this.groups = const [],
  });

  final SessionGroupsStatus status;
  final String workspaceId;
  final List<SessionGroup> groups;

  bool get ready => status == SessionGroupsStatus.ready;

  SessionGroup? groupById(String groupId) {
    for (final group in groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  /// Ids of groups containing [sessionId] — drives context-menu checkmarks.
  Set<String> groupIdsContaining(String sessionId) => {
    for (final group in groups)
      if (group.sessionIds.contains(sessionId)) group.id,
  };

  SessionGroupsState copyWith({
    SessionGroupsStatus? status,
    String? workspaceId,
    List<SessionGroup>? groups,
  }) => SessionGroupsState(
    status: status ?? this.status,
    workspaceId: workspaceId ?? this.workspaceId,
    groups: groups ?? this.groups,
  );
}

/// Owns the manual session groups of one workspace: optimistic mutations with
/// whole-file persistence. One cubit per open workspace (see
/// `WorkspaceSessionGroupsRegistry`) so concurrent tabs share a single writer.
class SessionGroupsCubit extends Cubit<SessionGroupsState> {
  SessionGroupsCubit({SessionGroupRepository? repository, this.knownSessionIds})
    : _repository = repository ?? SessionGroupRepository(),
      super(const SessionGroupsState());

  final SessionGroupRepository _repository;

  /// Live workspace session ids; stale member ids are pruned from the file on
  /// every persist. Rendered blocks always filter unknown ids anyway.
  final Set<String> Function()? knownSessionIds;

  int _generation = 0;
  Future<void>? _pendingPersist;

  /// Loads (or switches to) [workspaceId]. A later load supersedes an earlier
  /// in-flight one via generation check. IO failures degrade to an empty
  /// ready state (same semantics as a corrupt file) instead of escaping as
  /// unhandled errors and wedging the cubit in `loading`.
  Future<void> load(String workspaceId) async {
    final id = workspaceId.trim();
    final generation = ++_generation;
    emit(SessionGroupsState(status: SessionGroupsStatus.loading, workspaceId: id));
    SessionGroupsFile file;
    try {
      file = await _repository.load(id);
    } on Object {
      if (generation != _generation || isClosed) return;
      emit(SessionGroupsState(status: SessionGroupsStatus.ready, workspaceId: id));
      return;
    }
    if (generation != _generation || isClosed) return;
    emit(
      SessionGroupsState(status: SessionGroupsStatus.ready, workspaceId: id, groups: file.groups),
    );
  }

  void createGroup(String name) => _mutate((state) {
    final trimmed = name.trim();
    if (!state.ready || trimmed.isEmpty) return state;
    return state.copyWith(
      groups: [...state.groups, SessionGroup(id: const Uuid().v4(), name: trimmed)],
    );
  });

  void renameGroup(String groupId, String name) => _mutate((state) {
    final trimmed = name.trim();
    if (!state.ready || trimmed.isEmpty) return state;
    return state.copyWith(
      groups: [
        for (final group in state.groups)
          if (group.id == groupId) group.copyWith(name: trimmed) else group,
      ],
    );
  });

  void deleteGroup(String groupId) => _mutate((state) {
    if (!state.ready) return state;
    return state.copyWith(
      groups: state.groups.where((group) => group.id != groupId).toList(),
    );
  });

  void addSession(String groupId, String sessionId) =>
      setMembership(groupId, sessionId, member: true);

  void removeSession(String groupId, String sessionId) =>
      setMembership(groupId, sessionId, member: false);

  /// Tag-style toggle: joining never leaves other groups, leaving never
  /// touches the session itself.
  void setMembership(String groupId, String sessionId, {required bool member}) =>
      _mutate((state) {
        if (!state.ready || sessionId.trim().isEmpty) return state;
        return state.copyWith(
          groups: [
            for (final group in state.groups)
              if (group.id == groupId)
                group.copyWith(
                  sessionIds: member
                      ? group.sessionIds.contains(sessionId)
                            ? group.sessionIds
                            : [...group.sessionIds, sessionId]
                      : group.sessionIds.where((id) => id != sessionId).toList(),
                )
              else group,
          ],
        );
      });

  void toggleCollapsed(String groupId) => _mutate((state) {
    if (!state.ready) return state;
    return state.copyWith(
      groups: [
        for (final group in state.groups)
          if (group.id == groupId) group.copyWith(collapsed: !group.collapsed) else group,
      ],
    );
  });

  void _mutate(SessionGroupsState Function(SessionGroupsState state) mutate) {
    final next = mutate(state);
    if (identical(next, state)) return;
    emit(next);
    unawaited(_enqueuePersist(next));
  }

  /// Serializes whole-file writes so an older snapshot can never land after a
  /// newer one; the last mutation always wins.
  Future<void> _enqueuePersist(SessionGroupsState next) {
    final task = (_pendingPersist ?? Future<void>.value())
        .then((_) => _persist(next));
    _pendingPersist = task;
    return task;
  }

  Future<void> _persist(SessionGroupsState next) async {
    var groups = next.groups;
    try {
      final known = knownSessionIds?.call();
      if (known != null && known.isNotEmpty) {
        groups = [
          for (final group in groups)
            group.copyWith(
              sessionIds: [
                for (final id in group.sessionIds)
                  if (known.contains(id)) id,
              ],
            ),
        ];
      }
      await _repository.save(next.workspaceId, SessionGroupsFile(groups: groups));
    } on Object {
      // Callback or IO failures keep the optimistic state; the next mutation
      // retries the save.
    }
  }
}
