import 'package:flutter/foundation.dart';

enum AppSessionLaunchState {
  created,
  started,
}

@immutable
class AppSession {
  const AppSession({
    required this.sessionId,
    required this.projectId,
    required this.primaryPath,
    this.additionalPaths = const [],
    this.display = '',
    this.sessionTeam = '',
    this.launchState = AppSessionLaunchState.created,
    required this.createdAt,
    this.updatedAt = 0,
  });

  factory AppSession.fromJson(Map<String, Object?> json) {
    final launchRaw = json['launchState'] as String? ?? 'created';
    final launch = AppSessionLaunchState.values.firstWhere(
      (e) => e.name == launchRaw,
      orElse: () => AppSessionLaunchState.created,
    );
    final add = json['additionalPaths'];
    final paths = add is List
        ? add.map((e) => '$e').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    return AppSession(
      sessionId: json['sessionId'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      primaryPath: json['primaryPath'] as String? ?? '',
      additionalPaths: paths,
      display: json['display'] as String? ?? '',
      sessionTeam: json['sessionTeam'] as String? ?? '',
      launchState: launch,
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }

  final String sessionId;
  final String projectId;
  final String primaryPath;
  final List<String> additionalPaths;
  final String display;
  final String sessionTeam;
  final AppSessionLaunchState launchState;
  final int createdAt;
  final int updatedAt;

  String resolveDisplayTitle(String whenDisplayEmpty) =>
      display.isNotEmpty ? display : whenDisplayEmpty;

  AppSession copyWith({
    String? sessionId,
    String? projectId,
    String? primaryPath,
    List<String>? additionalPaths,
    String? display,
    String? sessionTeam,
    AppSessionLaunchState? launchState,
    int? createdAt,
    int? updatedAt,
  }) {
    return AppSession(
      sessionId: sessionId ?? this.sessionId,
      projectId: projectId ?? this.projectId,
      primaryPath: primaryPath ?? this.primaryPath,
      additionalPaths: additionalPaths ?? this.additionalPaths,
      display: display ?? this.display,
      sessionTeam: sessionTeam ?? this.sessionTeam,
      launchState: launchState ?? this.launchState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 1,
      'sessionId': sessionId,
      'projectId': projectId,
      'primaryPath': primaryPath,
      'additionalPaths': additionalPaths,
      'display': display,
      'sessionTeam': sessionTeam,
      'launchState': launchState.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppSession &&
            runtimeType == other.runtimeType &&
            sessionId == other.sessionId &&
            projectId == other.projectId &&
            primaryPath == other.primaryPath &&
            listEquals(additionalPaths, other.additionalPaths) &&
            display == other.display &&
            sessionTeam == other.sessionTeam &&
            launchState == other.launchState &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        sessionId,
        projectId,
        primaryPath,
        Object.hashAll(additionalPaths),
        display,
        sessionTeam,
        launchState,
        createdAt,
        updatedAt,
      );
}
