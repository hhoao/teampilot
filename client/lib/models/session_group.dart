import 'package:flutter/foundation.dart';

/// One manual session group ("todo", "review", …) in a workspace sidebar.
///
/// Membership is tag-style: the same session id may appear in several groups,
/// and grouped sessions stay in the main conversation list.
@immutable
class SessionGroup {
  const SessionGroup({
    required this.id,
    required this.name,
    this.sessionIds = const [],
    this.collapsed = false,
  });

  /// Tolerant decode: junk fields fall back to defaults instead of throwing;
  /// blank/duplicate member ids are dropped.
  factory SessionGroup.fromJson(Map<String, Object?> json) {
    final rawIds = json['sessionIds'];
    final ids = <String>{
      if (rawIds is List)
        for (final entry in rawIds)
          if (entry is String && entry.trim().isNotEmpty) entry,
    };
    return SessionGroup(
      id: json['id'] is String ? (json['id'] as String).trim() : '',
      name: json['name'] is String ? json['name'] as String : '',
      sessionIds: ids.toList(),
      collapsed: json['collapsed'] == true,
    );
  }

  final String id;

  /// Display label; may be any non-empty user-entered text.
  final String name;

  /// Member session ids in insertion order. Rendering re-sorts by the current
  /// sidebar sort, so no dedicated order is persisted.
  final List<String> sessionIds;

  /// Persisted block-collapse state.
  final bool collapsed;

  bool containsSession(String sessionId) => sessionIds.contains(sessionId);

  SessionGroup copyWith({
    String? name,
    List<String>? sessionIds,
    bool? collapsed,
  }) => SessionGroup(
    id: id,
    name: name ?? this.name,
    sessionIds: sessionIds ?? this.sessionIds,
    collapsed: collapsed ?? this.collapsed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'sessionIds': sessionIds,
    'collapsed': collapsed,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionGroup &&
          id == other.id &&
          name == other.name &&
          collapsed == other.collapsed &&
          listEquals(sessionIds, other.sessionIds);

  @override
  int get hashCode =>
      Object.hash(id, name, collapsed, Object.hashAll(sessionIds));
}

/// Root document of `{workspaceId}/session-groups.json`.
@immutable
class SessionGroupsFile {
  static const int currentVersion = 1;

  const SessionGroupsFile({
    this.version = currentVersion,
    this.groups = const [],
  });

  factory SessionGroupsFile.fromJson(Map<String, Object?> json) {
    final rawGroups = json['groups'];
    return SessionGroupsFile(
      version: json['version'] is int
          ? json['version'] as int
          : currentVersion,
      groups: [
        if (rawGroups is List)
          for (final entry in rawGroups)
            if (entry is Map)
              SessionGroup.fromJson(entry.cast<String, Object?>()),
      ],
    );
  }

  final int version;
  final List<SessionGroup> groups;

  Map<String, Object?> toJson() => {
    'version': version,
    'groups': [for (final group in groups) group.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionGroupsFile &&
          version == other.version &&
          listEquals(groups, other.groups);

  @override
  int get hashCode => Object.hash(version, Object.hashAll(groups));
}
