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
    this.workingDirectoryPath,
  });

  final bool isPersonal;

  /// Personal launch identity ([PersonalProfile.id]).
  final String personalProfileId;

  /// Active preset when [isPersonal] is true.
  final String? presetId;

  /// Selected team when [isPersonal] is false.
  final String? teamId;

  /// Primary working directory for the new session (workspace folder or worktree).
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
    Object? workingDirectoryPath = _unset,
  }) {
    return LandingLaunchContext(
      isPersonal: isPersonal ?? this.isPersonal,
      personalProfileId: personalProfileId ?? this.personalProfileId,
      presetId: presetId ?? this.presetId,
      teamId: teamId ?? this.teamId,
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
          workingDirectoryPath == other.workingDirectoryPath;

  @override
  int get hashCode => Object.hash(
    isPersonal,
    personalProfileId,
    presetId,
    teamId,
    workingDirectoryPath,
  );
}
