import 'package:flutter/foundation.dart';

import 'member_instance.dart';
import 'session_continue_overrides.dart';
import 'session_member_binding.dart';
import 'simple_launch_identity.dart';
import 'team_config.dart';
import 'workspace_folder.dart';
import 'workspace_topology.dart';

/// Runtime pods for [session.members], resolved from [team] member **types**.
///
/// Trusts session bindings as the pod list (createSession may have healed
/// expansion from workspace pins). Does **not** re-expand from
/// [TeamMemberConfig.replicas], which can lag behind disk after placement
/// saves — filtering an expand of stale replicas=1 drops `builder-0`/`builder-1`.
///
/// Lives here (not [member_instance.dart]) to avoid an AppSession import cycle
/// through [workspace_topology].
List<TeamMemberConfig> sessionRosterMembers(
  AppSession session,
  TeamProfile team,
) {
  final typesById = {for (final m in team.members) m.id: m};
  final poolSizeByType = <String, int>{};
  for (final b in session.members) {
    final type = _sessionBindingMemberType(b, typesById);
    if (type == null) continue;
    poolSizeByType[type.id] = (poolSizeByType[type.id] ?? 0) + 1;
  }

  final out = <TeamMemberConfig>[];
  for (final b in session.members) {
    final type = _sessionBindingMemberType(b, typesById);
    if (type == null) continue;
    final instanceId = b.rosterMemberId.trim();
    if (instanceId.isEmpty) continue;
    final pool = poolSizeByType[type.id] ?? 1;
    final ordinal = _sessionBindingOrdinal(instanceId, type.id);
    // Numbered ids need replicas > 1 so [MemberInstance] keeps `type-N` naming.
    final replicas = instanceId == type.id && pool <= 1
        ? 1
        : (pool > ordinal ? pool : ordinal + 1).clamp(2, 999);
    out.add(
      MemberInstance(
        type: type,
        ordinal: ordinal,
        replicas: replicas,
      ).toMemberConfig(),
    );
  }
  return out;
}

/// Pod list for Claude / native CLI roster writers (`config.json`, inboxes).
///
/// Same members as [sessionRosterMembers] today. Call sites that stage CLI
/// team files must use this (or [runtimeRosterMembers] without a session),
/// never raw [TeamProfile.members].
List<TeamMemberConfig> cliTeamRosterMembers(
  AppSession session,
  TeamProfile team,
) =>
    sessionRosterMembers(session, team);

TeamMemberConfig? _sessionBindingMemberType(
  SessionMemberBinding binding,
  Map<String, TeamMemberConfig> typesById,
) {
  final typeId = binding.typeId.trim();
  final direct = typesById[typeId];
  if (direct != null) return direct;
  final instanceId = binding.rosterMemberId.trim();
  final byInstance = typesById[instanceId];
  if (byInstance != null) return byInstance;
  final dash = instanceId.lastIndexOf('-');
  if (dash <= 0) return null;
  final suffix = instanceId.substring(dash + 1);
  if (int.tryParse(suffix) == null) return null;
  return typesById[instanceId.substring(0, dash)];
}

int _sessionBindingOrdinal(String instanceId, String typeId) {
  if (instanceId == typeId) return 0;
  final prefix = '$typeId-';
  if (!instanceId.startsWith(prefix)) return 0;
  return int.tryParse(instanceId.substring(prefix.length)) ?? 0;
}

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
    this.provider = '',
    this.model = '',
    this.effort = '',
    this.presetId = '',
    this.members = const [],
    this.nativeSessionIds = const {},
    this.launchState = AppSessionLaunchState.created,
    required this.createdAt,
    this.updatedAt = 0,
    this.pinned = false,
    this.sortOrder = 0,
    this.expertKey = '',
    this.continueOverrides = const SessionContinueOverrides(),
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
    String provider = '',
    String model = '',
    String effort = '',
    String presetId = '',
    List<SessionMemberBinding> members = const [],
    Map<String, String> nativeSessionIds = const {},
    AppSessionLaunchState launchState = AppSessionLaunchState.created,
    required int createdAt,
    int updatedAt = 0,
    bool pinned = false,
    int sortOrder = 0,
    String expertKey = '',
    SessionContinueOverrides continueOverrides =
        const SessionContinueOverrides(),
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
      provider: provider.trim(),
      model: model.trim(),
      effort: effort.trim(),
      presetId: presetId.trim(),
      members: members,
      nativeSessionIds: nativeSessionIds,
      launchState: launchState,
      createdAt: createdAt,
      updatedAt: updatedAt,
      pinned: pinned,
      sortOrder: sortOrder,
      expertKey: expertKey.trim(),
      continueOverrides: continueOverrides,
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
                (e) =>
                    SessionMemberBinding.fromJson(Map<String, Object?>.from(e)),
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
              if ('${e.key}'.trim().isNotEmpty &&
                  '${e.value}'.trim().isNotEmpty)
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
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      effort: json['effort'] as String? ?? '',
      presetId: json['presetId'] as String? ?? '',
      members: members,
      nativeSessionIds: native,
      launchState: launch,
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      pinned: json['pinned'] as bool? ?? false,
      sortOrder: json['sortOrder'] as int? ?? 0,
      expertKey: json['expertKey'] as String? ?? '',
      continueOverrides: SessionContinueOverrides.fromJson(
        json['continueOverrides'] is Map
            ? Map<String, Object?>.from(json['continueOverrides'] as Map)
            : null,
      ),
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
      return personalWorkDirsForPrimaryPath(folders, firstFolderPath);
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

  /// Simple launch: denormalized provider/model/effort (see [simpleIdentity]).
  final String provider;
  final String model;
  final String effort;

  /// Simple launch: provenance of the global CLI preset chosen at create.
  final String presetId;

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

  /// Expert Hub discovery key when this personal session summons an expert.
  final String expertKey;

  /// Session-scoped continue chrome: permission + per-member model overrides.
  final SessionContinueOverrides continueOverrides;

  /// True when this session has no team roster (Simple / unteamed).
  bool get isSimple => sessionTeam.trim().isEmpty;

  /// Denormalized Simple launch identity. Throws if this is a team session.
  /// Provider is returned as stored; legacy rows with an empty provider can be
  /// back-filled via [SimpleLaunchIdentity.withOfficialDefaultProvider] at the
  /// connect seam (the model never switches on [CliTool]).
  SimpleLaunchIdentity get simpleIdentity {
    if (!isSimple) {
      throw StateError('simpleIdentity requires a Simple (unteamed) session');
    }
    final resolvedCli = cli ?? CliTool.claude;
    return SimpleLaunchIdentity(
      cli: resolvedCli,
      provider: provider.trim(),
      model: model.trim(),
      effort: effort.trim(),
      expertKey: expertKey.trim(),
      presetId: presetId.trim(),
    );
  }

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
    String? provider,
    String? model,
    String? effort,
    String? presetId,
    List<SessionMemberBinding>? members,
    Map<String, String>? nativeSessionIds,
    AppSessionLaunchState? launchState,
    int? createdAt,
    int? updatedAt,
    bool? pinned,
    int? sortOrder,
    String? expertKey,
    SessionContinueOverrides? continueOverrides,
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
      provider: provider ?? this.provider,
      model: model ?? this.model,
      effort: effort ?? this.effort,
      presetId: presetId ?? this.presetId,
      members: members ?? this.members,
      nativeSessionIds: nativeSessionIds ?? this.nativeSessionIds,
      launchState: launchState ?? this.launchState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      sortOrder: sortOrder ?? this.sortOrder,
      expertKey: expertKey ?? this.expertKey,
      continueOverrides: continueOverrides ?? this.continueOverrides,
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
      if (provider.isNotEmpty) 'provider': provider,
      if (model.isNotEmpty) 'model': model,
      if (effort.isNotEmpty) 'effort': effort,
      if (presetId.isNotEmpty) 'presetId': presetId,
      if (members.isNotEmpty)
        'members': members.map((m) => m.toJson()).toList(),
      if (nativeSessionIds.isNotEmpty) 'nativeSessionIds': nativeSessionIds,
      'launchState': launchState.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'pinned': pinned,
      if (sortOrder != 0) 'sortOrder': sortOrder,
      if (expertKey.isNotEmpty) 'expertKey': expertKey,
      if (continueOverrides != const SessionContinueOverrides())
        'continueOverrides': continueOverrides.toJson(),
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
            provider == other.provider &&
            model == other.model &&
            effort == other.effort &&
            presetId == other.presetId &&
            listEquals(members, other.members) &&
            mapEquals(nativeSessionIds, other.nativeSessionIds) &&
            launchState == other.launchState &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            pinned == other.pinned &&
            sortOrder == other.sortOrder &&
            expertKey == other.expertKey &&
            continueOverrides == other.continueOverrides;
  }

  @override
  int get hashCode => Object.hashAll([
    sessionId,
    workspaceId,
    Object.hashAll(folders),
    Object.hashAll(memberTargets.entries),
    display,
    sessionTeam,
    profileId,
    cliTeamName,
    cli,
    provider,
    model,
    effort,
    presetId,
    Object.hashAll(members),
    Object.hashAll(
      nativeSessionIds.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    launchState,
    createdAt,
    updatedAt,
    pinned,
    sortOrder,
    expertKey,
    continueOverrides,
  ]);
}
