import 'package:flutter/foundation.dart';

@immutable
class AppProject {
  const AppProject({
    required this.projectId,
    required this.primaryPath,
    this.additionalPaths = const [],
    this.display = '',
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
      additionalPaths: paths,
      display: json['display'] as String? ?? '',
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      sessionIds: sessionIds,
    );
  }

  final String projectId;
  final String primaryPath;
  final List<String> additionalPaths;
  final String display;
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

  AppProject copyWith({
    String? projectId,
    String? primaryPath,
    List<String>? additionalPaths,
    String? display,
    int? createdAt,
    int? updatedAt,
    List<String>? sessionIds,
  }) {
    return AppProject(
      projectId: projectId ?? this.projectId,
      primaryPath: primaryPath ?? this.primaryPath,
      additionalPaths: additionalPaths ?? this.additionalPaths,
      display: display ?? this.display,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionIds: sessionIds ?? this.sessionIds,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'projectId': projectId,
      'primaryPath': primaryPath,
      'additionalPaths': additionalPaths,
      'display': display,
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
            listEquals(additionalPaths, other.additionalPaths) &&
            display == other.display &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            listEquals(sessionIds, other.sessionIds);
  }

  @override
  int get hashCode => Object.hash(
        projectId,
        primaryPath,
        Object.hashAll(additionalPaths),
        display,
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
