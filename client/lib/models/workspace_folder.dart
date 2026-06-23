import 'package:flutter/foundation.dart';

/// A workspace directory plus the machine ("target") it lives on.
///
/// Preparation phase: `targetId` is always [localTargetId]. P2 of the remote
/// execution architecture sets it to `ssh:*` / `wsl:*` per folder.
@immutable
class WorkspaceFolder {
  const WorkspaceFolder({required this.path, this.targetId = localTargetId});

  static const String localTargetId = 'local';

  final String path;
  final String targetId;

  factory WorkspaceFolder.fromJson(Map<String, Object?> json) {
    final id = (json['targetId'] as String?)?.trim();
    return WorkspaceFolder(
      path: json['path'] as String? ?? '',
      targetId: id == null || id.isEmpty ? localTargetId : id,
    );
  }

  Map<String, Object?> toJson() => {'path': path, 'targetId': targetId};

  WorkspaceFolder copyWith({String? path, String? targetId}) => WorkspaceFolder(
    path: path ?? this.path,
    targetId: targetId ?? this.targetId,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceFolder &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          targetId == other.targetId;

  @override
  int get hashCode => Object.hash(path, targetId);
}

/// Strict reader for the `folders` array — the only on-disk shape.
List<WorkspaceFolder> foldersFromJson(Object? raw) => raw is List
    ? [
        for (final e in raw)
          if (e is Map<String, Object?>) WorkspaceFolder.fromJson(e),
      ]
    : const [];
