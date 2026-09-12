import 'package:flutter/foundation.dart';

import 'app_session.dart';

/// Sidebar-row snapshot of an [AppSession].
///
/// Omits folders, members, and other document fields so a workspace can paint
/// the conversation list from one `sessions-index.json` instead of N
/// `session.json` files.
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

  /// List-row [AppSession]: row fields only; folders and members stay empty.
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
      if (purpose != SessionPurpose.normal) 'purpose': purpose.value,
      if (workflowId.isNotEmpty) 'workflowId': workflowId,
    };
  }
}
