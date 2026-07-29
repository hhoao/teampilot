import 'package:flutter/foundation.dart';

import 'team_config.dart';

/// Snapshot of compose-landing choices used to create a new session.
@immutable
class LandingLaunchContext {
  static const Object _unset = Object();

  const LandingLaunchContext({
    required this.isPersonal,
    this.presetId,
    this.teamId,
    this.projectFolderPath,
    this.expertKey,
    this.workingDirectoryPath,
    this.dangerouslySkipPermissions = true,
    this.cli,
    this.provider,
    this.model,
    this.effort,
  });

  /// True when launching Simple (unteamed) mode — empty [sessionTeam].
  final bool isPersonal;

  /// Active preset when [isPersonal] is true.
  final String? presetId;

  /// Selected team when [isPersonal] is false.
  final String? teamId;

  /// Workspace folder (git project root) for the new session.
  final String? projectFolderPath;

  /// Expert Hub member key when [isPersonal] is true (Simple mode).
  final String? expertKey;

  /// Launch cwd: the selected worktree path under [projectFolderPath].
  final String? workingDirectoryPath;

  /// When true, new sessions start with session-level full-access permission.
  final bool dangerouslySkipPermissions;

  /// Custom Simple launch CLI when [isPersonal] is true and no [presetId].
  final CliTool? cli;

  /// Custom Simple launch provider id.
  final String? provider;

  /// Custom Simple launch model id.
  final String? model;

  /// Custom Simple launch effort tier.
  final String? effort;

  LandingLaunchContext copyWith({
    bool? isPersonal,
    Object? presetId = _unset,
    String? teamId,
    Object? projectFolderPath = _unset,
    Object? expertKey = _unset,
    Object? workingDirectoryPath = _unset,
    bool? dangerouslySkipPermissions,
    Object? cli = _unset,
    Object? provider = _unset,
    Object? model = _unset,
    Object? effort = _unset,
  }) {
    return LandingLaunchContext(
      isPersonal: isPersonal ?? this.isPersonal,
      presetId: presetId == _unset ? this.presetId : presetId as String?,
      teamId: teamId ?? this.teamId,
      projectFolderPath: projectFolderPath == _unset
          ? this.projectFolderPath
          : projectFolderPath as String?,
      expertKey: expertKey == _unset ? this.expertKey : expertKey as String?,
      workingDirectoryPath: workingDirectoryPath == _unset
          ? this.workingDirectoryPath
          : workingDirectoryPath as String?,
      dangerouslySkipPermissions:
          dangerouslySkipPermissions ?? this.dangerouslySkipPermissions,
      cli: cli == _unset ? this.cli : cli as CliTool?,
      provider: provider == _unset ? this.provider : provider as String?,
      model: model == _unset ? this.model : model as String?,
      effort: effort == _unset ? this.effort : effort as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LandingLaunchContext &&
          isPersonal == other.isPersonal &&
          presetId == other.presetId &&
          teamId == other.teamId &&
          projectFolderPath == other.projectFolderPath &&
          expertKey == other.expertKey &&
          workingDirectoryPath == other.workingDirectoryPath &&
          dangerouslySkipPermissions == other.dangerouslySkipPermissions &&
          cli == other.cli &&
          provider == other.provider &&
          model == other.model &&
          effort == other.effort;

  @override
  int get hashCode => Object.hash(
    isPersonal,
    presetId,
    teamId,
    projectFolderPath,
    expertKey,
    workingDirectoryPath,
    dangerouslySkipPermissions,
    cli,
    provider,
    model,
    effort,
  );
}
