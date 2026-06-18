import 'package:flutter/foundation.dart';

import 'workspace_icon_ref.dart';

@immutable
class Workspace {
  const Workspace({
    required this.workspaceId,
    required this.primaryPath,
    this.additionalPaths = const [],
    this.display = '',
    this.defaultIdentityId = '',
    this.icon = WorkspaceIconRef.auto,
    required this.createdAt,
    this.updatedAt = 0,
    this.sessionIds = const [],
  });

  factory Workspace.fromJson(Map<String, Object?> json) {
    final add = json['additionalPaths'];
    final paths = add is List
        ? add.map((e) => '$e').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    final ids = json['sessionIds'];
    final sessionIds = ids is List
        ? ids.map((e) => '$e').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    return Workspace(
      workspaceId: json['workspaceId'] as String? ?? '',
      primaryPath: json['primaryPath'] as String? ?? '',
      additionalPaths: paths,
      display: json['display'] as String? ?? '',
      defaultIdentityId: json['defaultIdentityId'] as String? ?? '',
      icon: WorkspaceIconRef.fromJson(json['icon']),
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      sessionIds: sessionIds,
    );
  }

  final String workspaceId;
  final String primaryPath;
  final List<String> additionalPaths;
  final String display;
  final String defaultIdentityId;
  final WorkspaceIconRef icon;
  final int createdAt;
  final int updatedAt;
  final List<String> sessionIds;

  String get effectiveDisplay =>
      display.isNotEmpty ? display : _basename(primaryPath);

  static String _basename(String path) {
    if (path.isEmpty) return '';
    final parts = path.replaceAll(r'\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  Workspace copyWith({
    String? workspaceId,
    String? primaryPath,
    List<String>? additionalPaths,
    String? display,
    String? defaultIdentityId,
    WorkspaceIconRef? icon,
    int? createdAt,
    int? updatedAt,
    List<String>? sessionIds,
  }) {
    return Workspace(
      workspaceId: workspaceId ?? this.workspaceId,
      primaryPath: primaryPath ?? this.primaryPath,
      additionalPaths: additionalPaths ?? this.additionalPaths,
      display: display ?? this.display,
      defaultIdentityId: defaultIdentityId ?? this.defaultIdentityId,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionIds: sessionIds ?? this.sessionIds,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'workspaceId': workspaceId,
      'primaryPath': primaryPath,
      'additionalPaths': additionalPaths,
      'display': display,
      if (defaultIdentityId.isNotEmpty) 'defaultIdentityId': defaultIdentityId,
      if (icon.toJson() case final json?) 'icon': json,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'sessionIds': sessionIds,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Workspace &&
            runtimeType == other.runtimeType &&
            workspaceId == other.workspaceId &&
            primaryPath == other.primaryPath &&
            listEquals(additionalPaths, other.additionalPaths) &&
            display == other.display &&
            defaultIdentityId == other.defaultIdentityId &&
            icon == other.icon &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            listEquals(sessionIds, other.sessionIds);
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    primaryPath,
    Object.hashAll(additionalPaths),
    display,
    defaultIdentityId,
    icon,
    createdAt,
    updatedAt,
    Object.hashAll(sessionIds),
  );
}

class WorkspacesIndex {
  const WorkspacesIndex({this.schemaVersion = 1, this.workspaces = const []});

  factory WorkspacesIndex.fromJson(Map<String, Object?> json) {
    final raw = json['workspaces'];
    final list = <Workspace>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, Object?>) {
          list.add(Workspace.fromJson(item));
        }
      }
    }
    return WorkspacesIndex(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      workspaces: list,
    );
  }

  final int schemaVersion;
  final List<Workspace> workspaces;

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'workspaces': workspaces.map((p) => p.toJson()).toList(),
    };
  }
}
