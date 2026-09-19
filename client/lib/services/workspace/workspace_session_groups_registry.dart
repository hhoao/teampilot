import 'dart:async';

import '../../cubits/session_groups_cubit.dart';
import '../storage/home_storage.dart';

/// Retains long-lived [SessionGroupsCubit]s per open workspace so multiple
/// tabs on the same workspace share one owner/writer of session-groups.json.
class WorkspaceSessionGroupsRegistry {
  WorkspaceSessionGroupsRegistry({
    required HomeStorage storage,
    SessionGroupsCubit Function()? cubitFactory,
  }) : _cubitFactory =
           cubitFactory ?? (() => SessionGroupsCubit(storage: storage));

  final SessionGroupsCubit Function() _cubitFactory;
  final Map<String, SessionGroupsCubit> _cubits = {};

  /// Returns the retained cubit for [workspaceId], creating and loading it on
  /// first request. Throws on an empty id — callers always have a workspace.
  SessionGroupsCubit cubitFor(String workspaceId) {
    final ws = workspaceId.trim();
    if (ws.isEmpty) {
      throw ArgumentError.value(
        workspaceId,
        'workspaceId',
        'must not be empty',
      );
    }
    final existing = _cubits[ws];
    if (existing != null && !existing.isClosed) return existing;
    final cubit = _cubitFactory();
    _cubits[ws] = cubit;
    unawaited(cubit.load(ws));
    return cubit;
  }

  /// Closes the cubit when a workspace tab closes.
  void removeWorkspace(String workspaceId) {
    final ws = workspaceId.trim();
    if (ws.isEmpty) return;
    _cubits.remove(ws)?.close();
  }

  void dispose() {
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    _cubits.clear();
  }
}
