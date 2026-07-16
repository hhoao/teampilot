import '../../models/app_session.dart';

/// Rebuilds a full workspace session-id order after the user reorders one
/// worktree/project subgroup.
///
/// Walks [workspaceOrderedIds] and, whenever an id belongs to the group,
/// takes the next id from [groupOrderedIds] instead — preserving relative
/// positions of sessions outside the group.
List<String> mergeGroupSessionReorder({
  required List<String> workspaceOrderedIds,
  required List<String> groupOrderedIds,
}) {
  final groupSet = groupOrderedIds.toSet();
  if (groupSet.isEmpty) return workspaceOrderedIds;
  var gi = 0;
  return [
    for (final id in workspaceOrderedIds)
      if (groupSet.contains(id))
        groupOrderedIds[gi++]
      else
        id,
  ];
}

/// Applies a local reorder within [visibleIds] (e.g. the capped top-N rows)
/// then appends any remaining [allIds] that were not in the visible window.
///
/// [newIndex] uses [ReorderableListView.onReorderItem] semantics: it is already
/// the insertion index after the item at [oldIndex] has been removed.
List<String> reorderVisibleSessionIds({
  required List<String> allIds,
  required List<String> visibleIds,
  required int oldIndex,
  required int newIndex,
}) {
  if (newIndex == oldIndex) return allIds;
  final reorderedVisible = List<String>.of(visibleIds);
  final moved = reorderedVisible.removeAt(oldIndex);
  reorderedVisible.insert(newIndex, moved);
  if (visibleIds.length >= allIds.length) return reorderedVisible;
  final visibleSet = visibleIds.toSet();
  return [
    ...reorderedVisible,
    for (final id in allIds)
      if (!visibleSet.contains(id)) id,
  ];
}

/// Session ids in the order [sortAppSessions] would show them.
List<String> sessionIdsInSortOrder(List<AppSession> sessions) => [
  for (final s in sessions) s.sessionId,
];
