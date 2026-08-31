import 'package:flutter/foundation.dart';

import 'team_config.dart';
import 'launch_security_policy.dart';

/// Snapshot of compose-landing choices used to create a new session.
@immutable
class LandingLaunchContext {
  static const Object _unset = Object();

  const LandingLaunchContext({
    required this.isPersonal,
    bool generateLaunch = false,
    this.presetId,
    this.teamId,
    this.projectFolderPath,
    this.expertKey,
    this.workingDirectoryPath,
    this.launchSecurityPolicy = LaunchSecurityPolicy.fullAccess,
    this.cli,
    this.provider,
    this.model,
    this.effort,
  }) : generateLaunch = !isPersonal && generateLaunch;

  /// True when launching Simple (unteamed) mode — empty [sessionTeam].
  final bool isPersonal;

  /// True when Landing submits into the AI team-generation flow (team mode only).
  final bool generateLaunch;

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

  /// Security policy for the new session.
  final LaunchSecurityPolicy launchSecurityPolicy;

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
    bool? generateLaunch,
    Object? presetId = _unset,
    String? teamId,
    Object? projectFolderPath = _unset,
    Object? expertKey = _unset,
    Object? workingDirectoryPath = _unset,
    LaunchSecurityPolicy? launchSecurityPolicy,
    Object? cli = _unset,
    Object? provider = _unset,
    Object? model = _unset,
    Object? effort = _unset,
  }) {
    final nextPersonal = isPersonal ?? this.isPersonal;
    return LandingLaunchContext(
      isPersonal: nextPersonal,
      generateLaunch: !nextPersonal && (generateLaunch ?? this.generateLaunch),
      presetId: presetId == _unset ? this.presetId : presetId as String?,
      teamId: teamId ?? this.teamId,
      projectFolderPath: projectFolderPath == _unset
          ? this.projectFolderPath
          : projectFolderPath as String?,
      expertKey: expertKey == _unset ? this.expertKey : expertKey as String?,
      workingDirectoryPath: workingDirectoryPath == _unset
          ? this.workingDirectoryPath
          : workingDirectoryPath as String?,
      launchSecurityPolicy: launchSecurityPolicy ?? this.launchSecurityPolicy,
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
          generateLaunch == other.generateLaunch &&
          presetId == other.presetId &&
          teamId == other.teamId &&
          projectFolderPath == other.projectFolderPath &&
          expertKey == other.expertKey &&
          workingDirectoryPath == other.workingDirectoryPath &&
          launchSecurityPolicy == other.launchSecurityPolicy &&
          cli == other.cli &&
          provider == other.provider &&
          model == other.model &&
          effort == other.effort;

  @override
  int get hashCode => Object.hash(
    isPersonal,
    generateLaunch,
    presetId,
    teamId,
    projectFolderPath,
    expertKey,
    workingDirectoryPath,
    launchSecurityPolicy,
    cli,
    provider,
    model,
    effort,
  );
}
