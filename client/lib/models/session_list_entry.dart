import 'package:flutter/foundation.dart';

import 'app_session.dart';
import 'team_config.dart';
import 'workspace_folder.dart';

/// Sidebar-row snapshot of an [AppSession].
///
/// Omits members and other document fields so a workspace can paint the
/// conversation list from one `sessions-index.json` instead of N
/// `session.json` files. Folder metadata stays in the index for sidebar
/// project/worktree grouping.
///
/// [acp]/[cli] stay in the index because they decide which runtime the row
/// gets ([AppSession.acp] gates the terminal-less ACP chat), so a row must not
/// be read as PTY while the full document is still unhydrated.
@immutable
class SessionListEntry {
  const SessionListEntry._({
    required this.sessionId,
    required this.display,
    required this.purpose,
    required this.workflowId,
    required this.sessionTeam,
    required this.createdAt,
    required this.updatedAt,
    required this.archived,
    required this.pinned,
    required this.sortOrder,
    required this.folders,
    required this.cli,
    required this.acp,
  });

  factory SessionListEntry({
    required String sessionId,
    String display = '',
    SessionPurpose purpose = SessionPurpose.normal,
    String workflowId = '',
    String sessionTeam = '',
    required int createdAt,
    int updatedAt = 0,
    bool archived = false,
    bool pinned = false,
    int sortOrder = 0,
    List<WorkspaceFolder> folders = const [],
    CliTool? cli,
    bool acp = false,
  }) {
    return SessionListEntry._(
      sessionId: sessionId,
      display: display,
      purpose: purpose,
      workflowId: purpose == SessionPurpose.teamGeneration ? workflowId : '',
      sessionTeam: sessionTeam,
      createdAt: createdAt,
      updatedAt: updatedAt,
      archived: archived,
      pinned: pinned,
      sortOrder: sortOrder,
      folders: List<WorkspaceFolder>.unmodifiable(folders),
      cli: cli,
      acp: acp,
    );
  }

  factory SessionListEntry.fromJson(Map<String, Object?> json) {
    return SessionListEntry(
      sessionId: json['sessionId'] as String? ?? '',
      display: json['display'] as String? ?? '',
      purpose: SessionPurpose.decode(json['purpose']),
      workflowId: json['workflowId'] as String? ?? '',
      sessionTeam: json['sessionTeam'] as String? ?? '',
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      archived: json['archived'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
      sortOrder: json['sortOrder'] as int? ?? 0,
      folders: foldersFromJson(json['folders']),
      cli: CliTool.tryParse(json['cli'] as String?),
      acp: json['acp'] == true,
    );
  }

  factory SessionListEntry.fromSession(AppSession session) {
    return SessionListEntry(
      sessionId: session.sessionId,
      display: session.display,
      purpose: session.purpose,
      workflowId: session.workflowId,
      sessionTeam: session.sessionTeam,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      archived: session.archived,
      pinned: session.pinned,
      sortOrder: session.sortOrder,
      folders: session.folders,
      cli: session.cli,
      acp: session.acp,
    );
  }

  final String sessionId;
  final String display;
  final SessionPurpose purpose;
  final String workflowId;
  final String sessionTeam;
  final int createdAt;
  final int updatedAt;
  final bool archived;
  final bool pinned;
  final int sortOrder;
  final List<WorkspaceFolder> folders;

  /// Denormalized Simple launch CLI; null for team rows and legacy indexes.
  final CliTool? cli;

  /// Denormalized [AppSession.acp]; false for team rows and legacy indexes.
  final bool acp;

  /// List-row [AppSession]: row fields plus folder metadata; members stay
  /// empty.
  AppSession toListSession(String workspaceId) {
    return AppSession(
      sessionId: sessionId,
      workspaceId: workspaceId,
      display: display,
      purpose: purpose,
      workflowId: workflowId,
      sessionTeam: sessionTeam,
      createdAt: createdAt,
      updatedAt: updatedAt,
      archived: archived,
      pinned: pinned,
      sortOrder: sortOrder,
      folders: folders,
      cli: cli,
      acp: acp,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'sessionId': sessionId,
      'display': display,
      if (sessionTeam.isNotEmpty) 'sessionTeam': sessionTeam,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'pinned': pinned,
      if (sortOrder != 0) 'sortOrder': sortOrder,
      if (archived) 'archived': archived,
      if (folders.isNotEmpty)
        'folders': [for (final folder in folders) folder.toJson()],
      if (purpose != SessionPurpose.normal) 'purpose': purpose.value,
      if (workflowId.isNotEmpty) 'workflowId': workflowId,
      if (cli != null) 'cli': cli!.value,
      'acp': acp,
    };
  }
}
