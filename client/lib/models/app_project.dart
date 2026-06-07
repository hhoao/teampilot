import 'package:flutter/foundation.dart';

import 'project_icon_ref.dart';

@immutable
class AppProject {
  /// Reserved [projectId] for the built-in personal workspace project. Seeded at
  /// bootstrap, pinned first in the title bar, and not deletable/closable.
  static const String defaultPersonalId = 'default-personal';

  const AppProject({
    required this.projectId,
    required this.primaryPath,
    this.teamId = '',
    this.additionalPaths = const [],
    this.display = '',
    this.icon = ProjectIconRef.auto,
    required this.createdAt,
    this.updatedAt = 0,
    this.sessionIds = const [],
  });

  factory AppProject.fromJson(Map<String, Object?> json) {
    final add = json['additionalPaths'];
    final paths = add is List
        ? add.map((e) => '$e').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    final ids = json['sessionIds'];
    final sessionIds = ids is List
        ? ids.map((e) => '$e').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    return AppProject(
      projectId: json['projectId'] as String? ?? '',
      primaryPath: json['primaryPath'] as String? ?? '',
      teamId: json['teamId'] as String? ?? '',
      additionalPaths: paths,
      display: json['display'] as String? ?? '',
      icon: ProjectIconRef.fromJson(json['icon']),
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      sessionIds: sessionIds,
    );
  }

  final String projectId;
  final String primaryPath;
  final String teamId;
  final List<String> additionalPaths;
  final String display;
  final ProjectIconRef icon;
  final int createdAt;
  final int updatedAt;
  final List<String> sessionIds;

  /// The built-in personal project: pinned in the title bar, never deletable.
  bool get isDefaultPersonal =>
      projectId == defaultPersonalId && teamId.isEmpty;

  String get effectiveDisplay =>
      display.isNotEmpty ? display : _basename(primaryPath);

  static String _basename(String path) {
    if (path.isEmpty) return '';
    final parts = path.replaceAll(r'\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  AppProject copyWith({
    String? projectId,
    String? primaryPath,
    String? teamId,
    List<String>? additionalPaths,
    String? display,
    ProjectIconRef? icon,
    int? createdAt,
    int? updatedAt,
    List<String>? sessionIds,
  }) {
    return AppProject(
      projectId: projectId ?? this.projectId,
      primaryPath: primaryPath ?? this.primaryPath,
      teamId: teamId ?? this.teamId,
      additionalPaths: additionalPaths ?? this.additionalPaths,
      display: display ?? this.display,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionIds: sessionIds ?? this.sessionIds,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'projectId': projectId,
      'primaryPath': primaryPath,
      'teamId': teamId,
      'additionalPaths': additionalPaths,
      'display': display,
      if (icon.toJson() case final json?) 'icon': json,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'sessionIds': sessionIds,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppProject &&
            runtimeType == other.runtimeType &&
            projectId == other.projectId &&
            primaryPath == other.primaryPath &&
            teamId == other.teamId &&
            listEquals(additionalPaths, other.additionalPaths) &&
            display == other.display &&
            icon == other.icon &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            listEquals(sessionIds, other.sessionIds);
  }

  @override
  int get hashCode => Object.hash(
    projectId,
    primaryPath,
    teamId,
    Object.hashAll(additionalPaths),
    display,
    icon,
    createdAt,
    updatedAt,
    Object.hashAll(sessionIds),
  );
}

class AppProjectsIndex {
  const AppProjectsIndex({this.schemaVersion = 1, this.projects = const []});

  factory AppProjectsIndex.fromJson(Map<String, Object?> json) {
    final raw = json['projects'];
    final list = <AppProject>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, Object?>) {
          list.add(AppProject.fromJson(item));
        }
      }
    }
    return AppProjectsIndex(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      projects: list,
    );
  }

  final int schemaVersion;
  final List<AppProject> projects;

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'projects': projects.map((p) => p.toJson()).toList(),
    };
  }
}
