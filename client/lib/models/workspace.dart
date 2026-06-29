import 'package:flutter/foundation.dart';

import 'workspace_folder.dart';
import 'workspace_icon_ref.dart';
import 'workspace_topology.dart';

@immutable
class Workspace {
  const Workspace._({
    required this.workspaceId,
    required this.folders,
    this.display = '',
    this.defaultProfileId = '',
    this.icon = WorkspaceIconRef.auto,
    required this.createdAt,
    this.updatedAt = 0,
    this.sessionIds = const [],
    this.memberTargetsByTeam = const {},
  });

  factory Workspace({
    required String workspaceId,
    List<WorkspaceFolder> folders = const [],
    String display = '',
    String defaultProfileId = '',
    WorkspaceIconRef icon = WorkspaceIconRef.auto,
    required int createdAt,
    int updatedAt = 0,
    List<String> sessionIds = const [],
    Map<String, MemberTargetAssignments> memberTargetsByTeam = const {},
  }) {
    return Workspace._(
      workspaceId: workspaceId,
      folders: List.unmodifiable(folders),
      display: display,
      defaultProfileId: defaultProfileId,
      icon: icon,
      createdAt: createdAt,
      updatedAt: updatedAt,
      sessionIds: sessionIds,
      memberTargetsByTeam: _freezeTargetsByTeam(memberTargetsByTeam),
    );
  }

  factory Workspace.fromJson(Map<String, Object?> json) {
    final ids = json['sessionIds'];
    final sessionIds = ids is List
        ? ids.map((e) => '$e').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    return Workspace(
      workspaceId: json['workspaceId'] as String? ?? '',
      folders: foldersFromJson(json['folders']),
      display: json['display'] as String? ?? '',
      defaultProfileId: json['defaultProfileId'] as String? ?? '',
      icon: WorkspaceIconRef.fromJson(json['icon']),
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      sessionIds: sessionIds,
      memberTargetsByTeam: _targetsByTeamFromJson(json['memberTargetsByTeam']),
    );
  }

  final String workspaceId;
  final List<WorkspaceFolder> folders;
  final String display;
  final String defaultProfileId;
  final WorkspaceIconRef icon;
  final int createdAt;
  final int updatedAt;
  final List<String> sessionIds;

  /// Remembered mixed-workspace machine pins keyed by team id.
  final Map<String, MemberTargetAssignments> memberTargetsByTeam;

  String get firstFolderPath => folders.isEmpty ? '' : folders.first.path;
  List<String> get extraFolderPaths => folders.length <= 1
      ? const []
      : folders.skip(1).map((f) => f.path).toList(growable: false);
  List<String> get folderPaths =>
      folders.map((f) => f.path).toList(growable: false);

  String get effectiveDisplay =>
      display.isNotEmpty ? display : _basename(firstFolderPath);

  /// Basename of [firstFolderPath]; empty when no primary directory is set.
  String get primaryDirectoryName => _basename(firstFolderPath);

  static String _basename(String path) {
    if (path.isEmpty) return '';
    final parts = path.replaceAll(r'\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  Workspace copyWith({
    String? workspaceId,
    List<WorkspaceFolder>? folders,
    String? display,
    String? defaultProfileId,
    WorkspaceIconRef? icon,
    int? createdAt,
    int? updatedAt,
    List<String>? sessionIds,
    Map<String, MemberTargetAssignments>? memberTargetsByTeam,
  }) {
    return Workspace(
      workspaceId: workspaceId ?? this.workspaceId,
      folders: folders ?? this.folders,
      display: display ?? this.display,
      defaultProfileId: defaultProfileId ?? this.defaultProfileId,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionIds: sessionIds ?? this.sessionIds,
      memberTargetsByTeam: memberTargetsByTeam ?? this.memberTargetsByTeam,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'workspaceId': workspaceId,
      'folders': folders.map((f) => f.toJson()).toList(),
      'display': display,
      if (defaultProfileId.isNotEmpty) 'defaultProfileId': defaultProfileId,
      if (icon.toJson() case final json?) 'icon': json,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'sessionIds': sessionIds,
      if (memberTargetsByTeam.isNotEmpty)
        'memberTargetsByTeam': {
          for (final e in memberTargetsByTeam.entries) e.key: e.value,
        },
    };
  }

  static Map<String, MemberTargetAssignments> _freezeTargetsByTeam(
    Map<String, MemberTargetAssignments> raw,
  ) {
    return Map<String, MemberTargetAssignments>.unmodifiable({
      for (final team in raw.entries)
        if (team.key.trim().isNotEmpty)
          team.key: Map<String, String>.unmodifiable({
            for (final member in team.value.entries)
              if (member.key.trim().isNotEmpty && member.value.trim().isNotEmpty)
                member.key.trim(): member.value.trim(),
          }),
    });
  }

  static Map<String, MemberTargetAssignments> _targetsByTeamFromJson(
    Object? raw,
  ) {
    if (raw is! Map) return const {};
    final out = <String, MemberTargetAssignments>{};
    for (final teamEntry in raw.entries) {
      final teamId = teamEntry.key.toString().trim();
      if (teamId.isEmpty || teamEntry.value is! Map) continue;
      final members = <String, String>{};
      for (final memberEntry in (teamEntry.value as Map).entries) {
        final memberId = memberEntry.key.toString().trim();
        final targetId = memberEntry.value?.toString().trim() ?? '';
        if (memberId.isEmpty || targetId.isEmpty) continue;
        members[memberId] = targetId;
      }
      if (members.isNotEmpty) out[teamId] = members;
    }
    return _freezeTargetsByTeam(out);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Workspace &&
            runtimeType == other.runtimeType &&
            workspaceId == other.workspaceId &&
            listEquals(folders, other.folders) &&
            display == other.display &&
            defaultProfileId == other.defaultProfileId &&
            icon == other.icon &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            listEquals(sessionIds, other.sessionIds) &&
            mapEquals(memberTargetsByTeam, other.memberTargetsByTeam);
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    Object.hashAll(folders),
    display,
    defaultProfileId,
    icon,
    createdAt,
    updatedAt,
    Object.hashAll(sessionIds),
    Object.hashAll(
      memberTargetsByTeam.entries.map(
        (e) => Object.hash(e.key, Object.hashAll(e.value.entries)),
      ),
    ),
  );
}

class WorkspacesIndex {
  const WorkspacesIndex({this.schemaVersion = 2, this.workspaces = const []});

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
      schemaVersion: json['schemaVersion'] as int? ?? 2,
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
