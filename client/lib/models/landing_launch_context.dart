import 'package:flutter/foundation.dart';

import 'automation_tab_scope.dart';

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

  /// Profile id for manage panel / automation scope.
  ///
  /// Simple uses the fixed [AutomationTabScope.simpleLaunchProfileId] key;
  /// team uses [teamId].
  String get profileId {
    if (isPersonal) return AutomationTabScope.simpleLaunchProfileId;
    return teamId?.trim() ?? '';
  }

  LandingLaunchContext copyWith({
    bool? isPersonal,
    String? presetId,
    String? teamId,
    Object? projectFolderPath = _unset,
    Object? expertKey = _unset,
    Object? workingDirectoryPath = _unset,
  }) {
    return LandingLaunchContext(
      isPersonal: isPersonal ?? this.isPersonal,
      presetId: presetId ?? this.presetId,
      teamId: teamId ?? this.teamId,
      projectFolderPath: projectFolderPath == _unset
          ? this.projectFolderPath
          : projectFolderPath as String?,
      expertKey: expertKey == _unset ? this.expertKey : expertKey as String?,
      workingDirectoryPath: workingDirectoryPath == _unset
          ? this.workingDirectoryPath
          : workingDirectoryPath as String?,
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
          workingDirectoryPath == other.workingDirectoryPath;

  @override
  int get hashCode => Object.hash(
    isPersonal,
    presetId,
    teamId,
    projectFolderPath,
    expertKey,
    workingDirectoryPath,
  );
}
