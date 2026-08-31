/// Frozen Landing/workspace launch input captured at job creation.
///
/// Typed enough to rebuild the destination launch, loose enough to survive
/// schema evolution of the surrounding documents. The security policy is
/// stored as its serialized value so the job does not re-derive policy
/// defaults at read time.
final class TeamGenerationLaunchSnapshot {
  const TeamGenerationLaunchSnapshot({
    required this.projectFolderPath,
    required this.workingDirectoryPath,
    required this.launchSecurityPolicyValue,
    required this.folderIds,
    required this.targetIds,
    required this.workspaceRevision,
    required this.capturedAt,
  });

  factory TeamGenerationLaunchSnapshot.fromJson(Map<String, Object?> json) {
    return TeamGenerationLaunchSnapshot(
      projectFolderPath: (json['projectFolderPath'] as String? ?? '').trim(),
      workingDirectoryPath:
          (json['workingDirectoryPath'] as String? ?? '').trim(),
      launchSecurityPolicyValue:
          (json['launchSecurityPolicy'] as String? ?? '').trim(),
      folderIds: List<String>.unmodifiable([
        for (final value in (json['folderIds'] as List? ?? const []))
          if (value is String && value.trim().isNotEmpty) value.trim(),
      ]),
      targetIds: List<String>.unmodifiable([
        for (final value in (json['targetIds'] as List? ?? const []))
          if (value is String && value.trim().isNotEmpty) value.trim(),
      ]),
      workspaceRevision: (json['workspaceRevision'] as String? ?? '').trim(),
      capturedAt: (json['capturedAt'] as num?)?.toInt() ?? 0,
    );
  }

  final String projectFolderPath;
  final String workingDirectoryPath;
  final String launchSecurityPolicyValue;
  final List<String> folderIds;
  final List<String> targetIds;

  /// Deterministic revision over the launch-relevant workspace fields.
  final String workspaceRevision;
  final int capturedAt;

  Map<String, Object?> toJson() => {
    if (projectFolderPath.isNotEmpty) 'projectFolderPath': projectFolderPath,
    if (workingDirectoryPath.isNotEmpty)
      'workingDirectoryPath': workingDirectoryPath,
    if (launchSecurityPolicyValue.isNotEmpty)
      'launchSecurityPolicy': launchSecurityPolicyValue,
    if (folderIds.isNotEmpty) 'folderIds': folderIds,
    if (targetIds.isNotEmpty) 'targetIds': targetIds,
    if (workspaceRevision.isNotEmpty) 'workspaceRevision': workspaceRevision,
    'capturedAt': capturedAt,
  };
}

/// Destination launch choices derived from the validated plan.
final class GeneratedDestinationLaunch {
  const GeneratedDestinationLaunch({
    required this.folderId,
    required this.projectFolderPath,
    required this.workingDirectoryPath,
    required this.leadTargetId,
  });

  factory GeneratedDestinationLaunch.fromJson(Map<String, Object?> json) {
    return GeneratedDestinationLaunch(
      folderId: (json['folderId'] as String? ?? '').trim(),
      projectFolderPath: (json['projectFolderPath'] as String? ?? '').trim(),
      workingDirectoryPath:
          (json['workingDirectoryPath'] as String? ?? '').trim(),
      leadTargetId: (json['leadTargetId'] as String? ?? '').trim(),
    );
  }

  final String folderId;
  final String projectFolderPath;
  final String workingDirectoryPath;
  final String leadTargetId;

  Map<String, Object?> toJson() => {
    'folderId': folderId,
    if (projectFolderPath.isNotEmpty) 'projectFolderPath': projectFolderPath,
    if (workingDirectoryPath.isNotEmpty)
      'workingDirectoryPath': workingDirectoryPath,
    if (leadTargetId.isNotEmpty) 'leadTargetId': leadTargetId,
  };
}
