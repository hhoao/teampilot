import 'package:flutter/foundation.dart';

import 'session_member_binding.dart';
import 'team_config.dart';
import 'workspace_folder.dart';
import 'workspace_topology.dart';

enum AppSessionLaunchState { created, started }

@immutable
class AppSession {
  const AppSession._({
    required this.sessionId,
    required this.workspaceId,
    required this.folders,
    this.memberTargets = const {},
    this.display = '',
    this.sessionTeam = '',
    this.profileId = '',
    this.cliTeamName = '',
    this.cli,
    this.members = const [],
    this.nativeSessionIds = const {},
    this.launchState = AppSessionLaunchState.created,
    required this.createdAt,
    this.updatedAt = 0,
    this.pinned = false,
    this.sortOrder = 0,
  });

  factory AppSession({
    required String sessionId,
    required String workspaceId,
    List<WorkspaceFolder> folders = const [],
    Map<String, String> memberTargets = const {},
    String display = '',
    String sessionTeam = '',
    String profileId = '',
    String cliTeamName = '',
    CliTool? cli,
    List<SessionMemberBinding> members = const [],
    Map<String, String> nativeSessionIds = const {},
    AppSessionLaunchState launchState = AppSessionLaunchState.created,
    required int createdAt,
    int updatedAt = 0,
    bool pinned = false,
    int sortOrder = 0,
  }) {
    return AppSession._(
      sessionId: sessionId,
      workspaceId: workspaceId,
      folders: List.unmodifiable(folders),
      memberTargets: Map.unmodifiable({
        for (final e in memberTargets.entries)
          if (e.key.trim().isNotEmpty && e.value.trim().isNotEmpty)
            e.key.trim(): e.value.trim(),
      }),
      display: display,
      sessionTeam: sessionTeam,
      profileId: profileId,
      cliTeamName: cliTeamName,
      cli: cli,
      members: members,
      nativeSessionIds: nativeSessionIds,
      launchState: launchState,
      createdAt: createdAt,
      updatedAt: updatedAt,
      pinned: pinned,
      sortOrder: sortOrder,
    );
  }

  factory AppSession.fromJson(Map<String, Object?> json) {
    final launchRaw = json['launchState'] as String? ?? 'created';
    final launch = AppSessionLaunchState.values.firstWhere(
      (e) => e.name == launchRaw,
      orElse: () => AppSessionLaunchState.created,
    );
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
    final nativeRaw = json['nativeSessionIds'];
    final native = nativeRaw is Map
        ? {
            for (final e in nativeRaw.entries)
              if (e.value != null) '${e.key}': '${e.value}',
          }
        : const <String, String>{};
    final targetsRaw = json['memberTargets'];
    final targets = targetsRaw is Map
        ? <String, String>{
            for (final e in targetsRaw.entries)
              if ('${e.key}'.trim().isNotEmpty && '${e.value}'.trim().isNotEmpty)
                '${e.key}'.trim(): '${e.value}'.trim(),
          }
        : const <String, String>{};
    return AppSession(
      sessionId: json['sessionId'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      folders: foldersFromJson(json['folders']),
      memberTargets: targets,
      display: json['display'] as String? ?? '',
      sessionTeam: json['sessionTeam'] as String? ?? '',
      profileId: json['profileId'] as String? ?? '',
      cliTeamName: json['cliTeamName'] as String? ?? '',
      cli: CliTool.tryParse(json['cli'] as String?),
      members: members,
      nativeSessionIds: native,
      launchState: launch,
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      pinned: json['pinned'] as bool? ?? false,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  final String sessionId;
  final String workspaceId;
  final List<WorkspaceFolder> folders;

  /// Mixed workspace: runtime instance id → machine target id.
  final Map<String, String> memberTargets;

  final String display;

  String get firstFolderPath => folders.isEmpty ? '' : folders.first.path;
  List<String> get extraFolderPaths => folders.length <= 1
      ? const []
      : folders.skip(1).map((f) => f.path).toList(growable: false);
  List<String> get folderPaths =>
      folders.map((f) => f.path).toList(growable: false);

  /// Working directory + add-dirs for [memberId] against [folders].
  ({String workingDirectory, List<String> addDirs}) workDirsForMember(
    String? memberId, {
    required List<WorkspaceFolder> folders,
  }) {
    if (memberId == null || memberId.trim().isEmpty) {
      return (workingDirectory: firstFolderPath, addDirs: extraFolderPaths);
    }
    final targetId = memberTargetForInstanceId(memberTargets, memberId);
    if (targetId == null) {
      return (workingDirectory: firstFolderPath, addDirs: extraFolderPaths);
    }
    final work = memberWorkDirsForTarget(folders, targetId);
    if (work.workingDirectory.isEmpty) {
      return (workingDirectory: firstFolderPath, addDirs: extraFolderPaths);
    }
    return work;
  }

  final String sessionTeam;
  final String profileId;
  final String cliTeamName;
  final CliTool? cli;
  final List<SessionMemberBinding> members;
  final Map<String, String> nativeSessionIds;

  AppSession withNativeSessionId(String toolValue, String nativeId) {
    final tool = toolValue.trim();
    final id = nativeId.trim();
    if (tool.isEmpty || id.isEmpty || nativeSessionIds[tool] == id) return this;
    return copyWith(nativeSessionIds: {...nativeSessionIds, tool: id});
  }

  final AppSessionLaunchState launchState;
  final int createdAt;
  final int updatedAt;
  final bool pinned;
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
    String? workspaceId,
    List<WorkspaceFolder>? folders,
    Map<String, String>? memberTargets,
    String? display,
    String? sessionTeam,
    String? profileId,
    String? cliTeamName,
    CliTool? cli,
    List<SessionMemberBinding>? members,
    Map<String, String>? nativeSessionIds,
    AppSessionLaunchState? launchState,
    int? createdAt,
    int? updatedAt,
    bool? pinned,
    int? sortOrder,
  }) {
    return AppSession(
      sessionId: sessionId ?? this.sessionId,
      workspaceId: workspaceId ?? this.workspaceId,
      folders: folders ?? this.folders,
      memberTargets: memberTargets ?? this.memberTargets,
      display: display ?? this.display,
      sessionTeam: sessionTeam ?? this.sessionTeam,
      profileId: profileId ?? this.profileId,
      cliTeamName: cliTeamName ?? this.cliTeamName,
      cli: cli ?? this.cli,
      members: members ?? this.members,
      nativeSessionIds: nativeSessionIds ?? this.nativeSessionIds,
      launchState: launchState ?? this.launchState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 2,
      'sessionId': sessionId,
      'workspaceId': workspaceId,
      'folders': folders.map((f) => f.toJson()).toList(),
      if (memberTargets.isNotEmpty) 'memberTargets': memberTargets,
      'display': display,
      'sessionTeam': sessionTeam,
      if (profileId.isNotEmpty) 'profileId': profileId,
      if (cliTeamName.isNotEmpty) 'cliTeamName': cliTeamName,
      if (cli != null) 'cli': cli!.value,
      if (members.isNotEmpty)
        'members': members.map((m) => m.toJson()).toList(),
      if (nativeSessionIds.isNotEmpty) 'nativeSessionIds': nativeSessionIds,
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
            workspaceId == other.workspaceId &&
            listEquals(folders, other.folders) &&
            mapEquals(memberTargets, other.memberTargets) &&
            display == other.display &&
            sessionTeam == other.sessionTeam &&
            profileId == other.profileId &&
            cliTeamName == other.cliTeamName &&
            cli == other.cli &&
            listEquals(members, other.members) &&
            mapEquals(nativeSessionIds, other.nativeSessionIds) &&
            launchState == other.launchState &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            pinned == other.pinned &&
            sortOrder == other.sortOrder;
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    workspaceId,
    Object.hashAll(folders),
    Object.hashAll(memberTargets.entries),
    display,
    sessionTeam,
    profileId,
    cliTeamName,
    cli,
    Object.hashAll(members),
    Object.hashAll(
      nativeSessionIds.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    launchState,
    createdAt,
    updatedAt,
    pinned,
    sortOrder,
  );
}
