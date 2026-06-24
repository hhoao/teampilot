import 'package:flutter/foundation.dart';

import 'session_member_binding.dart';
import 'team_config.dart';
import 'workspace_folder.dart';

enum AppSessionLaunchState { created, started }

@immutable
class AppSession {
  const AppSession._({
    required this.sessionId,
    required this.workspaceId,
    required this.folders,
    this.folderAssignments = const {},
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
    Map<String, List<String>> folderAssignments = const {},
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
      folderAssignments: Map.unmodifiable({
        for (final e in folderAssignments.entries)
          e.key: List<String>.unmodifiable(e.value),
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
    final assignRaw = json['folderAssignments'];
    final assignments = assignRaw is Map
        ? <String, List<String>>{
            for (final e in assignRaw.entries)
              if (e.value is List)
                '${e.key}': [
                  for (final p in (e.value as List))
                    if ('$p'.isNotEmpty) '$p',
                ],
          }
        : const <String, List<String>>{};
    return AppSession(
      sessionId: json['sessionId'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      folders: foldersFromJson(json['folders']),
      folderAssignments: assignments,
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

  /// P3a: per-member startup folder assignment (memberId → [folderPath...]).
  /// First path = that member's working directory; rest = `--add-dir`. A member
  /// with no entry inherits the workspace folders. All of a member's folders
  /// share one targetId (one agent, one machine).
  final Map<String, List<String>> folderAssignments;

  final String display;

  String get firstFolderPath => folders.isEmpty ? '' : folders.first.path;
  List<String> get extraFolderPaths => folders.length <= 1
      ? const []
      : folders.skip(1).map((f) => f.path).toList(growable: false);
  List<String> get folderPaths =>
      folders.map((f) => f.path).toList(growable: false);

  /// P3a: the working directory + `--add-dir` dirs for [memberId]. When the
  /// member has a non-empty [folderAssignments] entry, its first path is the
  /// working directory and the rest are add-dirs; otherwise the member inherits
  /// the session folders ([firstFolderPath] / [extraFolderPaths]). A null/empty
  /// [memberId] always inherits. Single source for per-member work-dir
  /// resolution (lifecycle launch, connect, and tab-store all delegate here).
  ({String workingDirectory, List<String> addDirs}) workDirsForMember(
    String? memberId,
  ) {
    final assigned = memberId == null ? null : folderAssignments[memberId];
    if (assigned == null || assigned.isEmpty) {
      return (workingDirectory: firstFolderPath, addDirs: extraFolderPaths);
    }
    return (
      workingDirectory: assigned.first,
      addDirs: assigned.skip(1).toList(growable: false),
    );
  }


  /// Stable UI team id ([TeamProfile.id]) for filtering; not the CLI runtime name.
  final String sessionTeam;

  /// Personal-session launch identity ([PersonalProfile.id]) this session was
  /// created under. Empty for team sessions and for legacy personal sessions
  /// that predate per-identity launches (resolved to the default personal at
  /// launch time). The personal analog of [sessionTeam].
  final String profileId;

  /// CLI `--team-name` / config-profiles member dir (`{teamId}-{seq}`).
  final String cliTeamName;

  /// Personal-workspace session override; when null, [PersonalProfile.cli] applies.
  final CliTool? cli;

  /// Per-roster-member CLI `--session-id` / `--resume` task ids.
  final List<SessionMemberBinding> members;

  /// Personal (single-agent) session's CLI-native resume ids keyed by
  /// [CliTool.value]. Team sessions carry these per member on [members];
  /// personal sessions have no roster, so they live here. Empty for
  /// `clientPinned` CLIs (native id == [sessionId]). See
  /// `docs/session-resume-architecture.md`.
  final Map<String, String> nativeSessionIds;

  /// Returns this session with [nativeId] recorded for [toolValue], or `this`
  /// unchanged when already equal.
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
    String? workspaceId,
    List<WorkspaceFolder>? folders,
    Map<String, List<String>>? folderAssignments,
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
      folderAssignments: folderAssignments ?? this.folderAssignments,
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
      if (folderAssignments.isNotEmpty) 'folderAssignments': folderAssignments,
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
            _assignmentsEqual(folderAssignments, other.folderAssignments) &&
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
    Object.hashAll(
      folderAssignments.entries.map(
        (e) => Object.hash(e.key, Object.hashAll(e.value)),
      ),
    ),
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

  static bool _assignmentsEqual(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !listEquals(entry.value, other)) return false;
    }
    return true;
  }
}
