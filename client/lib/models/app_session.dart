import 'package:flutter/foundation.dart';

import 'session_member_binding.dart';
import 'team_config.dart';

enum AppSessionLaunchState { created, started }

@immutable
class AppSession {
  const AppSession({
    required this.sessionId,
    required this.projectId,
    required this.primaryPath,
    this.additionalPaths = const [],
    this.display = '',
    this.sessionTeam = '',
    this.cliTeamName = '',
    this.cli,
    this.members = const [],
    this.launchState = AppSessionLaunchState.created,
    required this.createdAt,
    this.updatedAt = 0,
    this.pinned = false,
    this.sortOrder = 0,
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
    final membersRaw = json['members'];
    final members = membersRaw is List
        ? membersRaw
              .whereType<Map>()
              .map(
                (e) => SessionMemberBinding.fromJson(
                  Map<String, Object?>.from(e),
                ),
              )
              .toList()
        : const <SessionMemberBinding>[];
    return AppSession(
      sessionId: json['sessionId'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      primaryPath: json['primaryPath'] as String? ?? '',
      additionalPaths: paths,
      display: json['display'] as String? ?? '',
      sessionTeam: json['sessionTeam'] as String? ?? '',
      cliTeamName: json['cliTeamName'] as String? ?? '',
      cli: CliTool.tryParse(json['cli'] as String?),
      members: members,
      launchState: launch,
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      pinned: json['pinned'] as bool? ?? false,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  final String sessionId;
  final String projectId;
  final String primaryPath;
  final List<String> additionalPaths;
  final String display;

  /// Stable UI team id ([TeamConfig.id]) for filtering; not the CLI runtime name.
  final String sessionTeam;

  /// CLI `--team-name` / config-profiles member dir (`{teamId}-{seq}`).
  final String cliTeamName;

  /// Personal-project session override; when null, [ProjectProfile.cli] applies.
  final CliTool? cli;

  /// Per-roster-member CLI `--session-id` / `--resume` task ids.
  final List<SessionMemberBinding> members;

  final AppSessionLaunchState launchState;
  final int createdAt;
  final int updatedAt;
  final bool pinned;

  /// Manual ordering rank for [AppSessionSort.manual]. Lower sorts first;
  /// `0` (the default for never-reordered sessions) sorts above stamped rows.
  final int sortOrder;

  String resolveDisplayTitle(String whenDisplayEmpty) =>
      display.isNotEmpty ? display : whenDisplayEmpty;

  SessionMemberBinding? bindingFor(String rosterMemberId) {
    for (final binding in members) {
      if (binding.rosterMemberId == rosterMemberId) return binding;
    }
    return null;
  }

  SessionMemberBinding requireBinding(String rosterMemberId) =>
      bindingFor(rosterMemberId) ??
      (throw StateError('No task binding for roster member $rosterMemberId'));

  AppSession copyWith({
    String? sessionId,
    String? projectId,
    String? primaryPath,
    List<String>? additionalPaths,
    String? display,
    String? sessionTeam,
    String? cliTeamName,
    CliTool? cli,
    List<SessionMemberBinding>? members,
    AppSessionLaunchState? launchState,
    int? createdAt,
    int? updatedAt,
    bool? pinned,
    int? sortOrder,
  }) {
    return AppSession(
      sessionId: sessionId ?? this.sessionId,
      projectId: projectId ?? this.projectId,
      primaryPath: primaryPath ?? this.primaryPath,
      additionalPaths: additionalPaths ?? this.additionalPaths,
      display: display ?? this.display,
      sessionTeam: sessionTeam ?? this.sessionTeam,
      cliTeamName: cliTeamName ?? this.cliTeamName,
      cli: cli ?? this.cli,
      members: members ?? this.members,
      launchState: launchState ?? this.launchState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      sortOrder: sortOrder ?? this.sortOrder,
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
      if (cliTeamName.isNotEmpty) 'cliTeamName': cliTeamName,
      if (cli != null) 'cli': cli!.value,
      if (members.isNotEmpty)
        'members': members.map((m) => m.toJson()).toList(),
      'launchState': launchState.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'pinned': pinned,
      if (sortOrder != 0) 'sortOrder': sortOrder,
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
            cliTeamName == other.cliTeamName &&
            cli == other.cli &&
            listEquals(members, other.members) &&
            launchState == other.launchState &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            pinned == other.pinned &&
            sortOrder == other.sortOrder;
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    projectId,
    primaryPath,
    Object.hashAll(additionalPaths),
    display,
    sessionTeam,
    cliTeamName,
    cli,
    Object.hashAll(members),
    launchState,
    createdAt,
    updatedAt,
    pinned,
    sortOrder,
  );
}
