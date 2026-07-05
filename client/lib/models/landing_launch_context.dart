import 'package:flutter/foundation.dart';

import '../services/storage/launch_profile_provisioner.dart';

/// Snapshot of compose-landing choices used to create a new session.
@immutable
class LandingLaunchContext {
  static const Object _unset = Object();

  const LandingLaunchContext({
    required this.isPersonal,
    this.personalProfileId = '',
    this.presetId,
    this.teamId,
    this.projectFolderPath,
    this.expertKey,
    this.workingDirectoryPath,
  });

  final bool isPersonal;

  /// Personal launch identity ([PersonalProfile.id]).
  final String personalProfileId;

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
  String get profileId {
    if (isPersonal) {
      final id = personalProfileId.trim();
      return id.isNotEmpty ? id : LaunchProfileProvisioner.defaultPersonalId;
    }
    return teamId?.trim() ?? '';
  }

  LandingLaunchContext copyWith({
    bool? isPersonal,
    String? personalProfileId,
    String? presetId,
    String? teamId,
    Object? projectFolderPath = _unset,
    Object? expertKey = _unset,
    Object? workingDirectoryPath = _unset,
  }) {
    return LandingLaunchContext(
      isPersonal: isPersonal ?? this.isPersonal,
      personalProfileId: personalProfileId ?? this.personalProfileId,
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
          personalProfileId == other.personalProfileId &&
          presetId == other.presetId &&
          teamId == other.teamId &&
          projectFolderPath == other.projectFolderPath &&
          expertKey == other.expertKey &&
          workingDirectoryPath == other.workingDirectoryPath;

  @override
  int get hashCode => Object.hash(
    isPersonal,
    personalProfileId,
    presetId,
    teamId,
    projectFolderPath,
    expertKey,
    workingDirectoryPath,
  );
}
