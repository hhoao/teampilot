class RightToolOpenSet {
  const RightToolOpenSet({
    this.openIds = const [],
    this.selectedId,
    this.dismissedIds = const [],
  });

  static const knownIds = {
    'members',
    'fileTree',
    'git',
    'mailbox',
    'board',
    'search',
  };

  static const teamSeedIds = ['members', 'mailbox'];

  final List<String> openIds;
  final String? selectedId;
  final List<String> dismissedIds;

  static List<String> sanitizeIds(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value is! String || value.isEmpty) continue;
      if (!knownIds.contains(value)) continue;
      if (!seen.add(value)) continue;
      out.add(value);
    }
    return out;
  }

  static String? sanitizeSelected(Object? raw) {
    if (raw is! String || raw.isEmpty || !knownIds.contains(raw)) return null;
    return raw;
  }

  static RightToolOpenSet sanitize({
    required List<String> openIds,
    String? selectedId,
    required List<String> dismissedIds,
  }) {
    final open = sanitizeIds(openIds);
    final openSet = open.toSet();
    final dismissed = [
      for (final id in sanitizeIds(dismissedIds))
        if (!openSet.contains(id)) id,
    ];
    final selected = sanitizeSelected(selectedId);
    return RightToolOpenSet(
      openIds: open,
      selectedId: selected,
      dismissedIds: dismissed,
    );
  }

  List<String> visibleOpenIds(Iterable<String> catalog) {
    final available = catalog.toSet();
    return [for (final id in openIds) if (available.contains(id)) id];
  }

  String? visibleSelectedId(Iterable<String> catalog) {
    final visible = visibleOpenIds(catalog);
    if (selectedId != null && visible.contains(selectedId)) return selectedId;
    return visible.isEmpty ? null : visible.last;
  }

  RightToolOpenSet opened(String toolId) {
    if (!knownIds.contains(toolId)) return this;
    final open = [...openIds];
    if (!open.contains(toolId)) open.add(toolId);
    final dismissed = [for (final id in dismissedIds) if (id != toolId) id];
    if (_listEquals(open, openIds) &&
        selectedId == toolId &&
        _listEquals(dismissed, dismissedIds)) {
      return this;
    }
    return RightToolOpenSet(
      openIds: open,
      selectedId: toolId,
      dismissedIds: dismissed,
    );
  }

  RightToolOpenSet selected(String toolId) => opened(toolId);

  RightToolOpenSet closed(String toolId, {required Iterable<String> catalog}) {
    final index = openIds.indexOf(toolId);
    if (index < 0) return this;
    final open = [...openIds]..removeAt(index);
    final dismissed = dismissedIds.contains(toolId)
        ? dismissedIds
        : [...dismissedIds, toolId];
    String? selected = selectedId;
    if (selected == toolId) {
      final available = catalog.toSet();
      final before = visibleOpenIds(catalog);
      final visibleIndex = before.indexOf(toolId);
      final after = [for (final id in open) if (available.contains(id)) id];
      if (after.isEmpty) {
        selected = null;
      } else if (visibleIndex > 0) {
        selected = before[visibleIndex - 1];
      } else {
        selected = after.first;
      }
    }
    return RightToolOpenSet(
      openIds: open,
      selectedId: selected,
      dismissedIds: dismissed,
    );
  }

  RightToolOpenSet seededForTeam(Iterable<String> catalog) {
    final available = catalog.toSet();
    final open = [...openIds];
    final dismissed = dismissedIds.toSet();
    final added = <String>[];
    for (final id in teamSeedIds) {
      if (!available.contains(id)) continue;
      if (open.contains(id)) continue;
      if (dismissed.contains(id)) continue;
      open.add(id);
      added.add(id);
    }
    if (added.isEmpty) return this;
    final visible = [for (final id in open) if (available.contains(id)) id];
    var selected = selectedId;
    final hasVisibleSelection =
        selected != null && visible.contains(selected);
    if (!hasVisibleSelection && visible.isNotEmpty) {
      if (added.contains('members') && visible.contains('members')) {
        selected = 'members';
      } else {
        selected = added.firstWhere(
          visible.contains,
          orElse: () => visible.last,
        );
      }
    }
    return RightToolOpenSet(
      openIds: open,
      selectedId: selected,
      dismissedIds: dismissedIds,
    );
  }

  RightToolOpenSet copyWith({
    List<String>? openIds,
    String? selectedId,
    bool clearSelectedId = false,
    List<String>? dismissedIds,
  }) => RightToolOpenSet(
    openIds: openIds ?? this.openIds,
    selectedId: clearSelectedId ? null : (selectedId ?? this.selectedId),
    dismissedIds: dismissedIds ?? this.dismissedIds,
  );

  @override
  bool operator ==(Object other) =>
      other is RightToolOpenSet &&
      _listEquals(openIds, other.openIds) &&
      selectedId == other.selectedId &&
      _listEquals(dismissedIds, other.dismissedIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(openIds),
    selectedId,
    Object.hashAll(dismissedIds),
  );
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
