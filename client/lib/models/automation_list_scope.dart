import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'automation_tab_scope.dart';

/// Describes which automations a list view or cubit load should cover.
@immutable
class AutomationListScope extends Equatable {
  const AutomationListScope._({
    this.workspaceId,
    this.tabScope,
    this.sessionId,
  });

  /// Global management — every workspace and launch profile.
  const AutomationListScope.all() : this._();

  /// One workspace — personal plus every team store under [workspaceId].
  factory AutomationListScope.workspace(String workspaceId) {
    return AutomationListScope._(workspaceId: workspaceId.trim());
  }

  /// One launch-profile store, optionally narrowed to [sessionId].
  factory AutomationListScope.tab(
    AutomationTabScope tabScope, {
    String? sessionId,
  }) {
    final trimmedSession = sessionId?.trim();
    return AutomationListScope._(
      tabScope: tabScope,
      sessionId: trimmedSession == null || trimmedSession.isEmpty
          ? null
          : trimmedSession,
    );
  }

  final String? workspaceId;
  final AutomationTabScope? tabScope;
  final String? sessionId;

  bool get isAll => workspaceId == null && tabScope == null;
  bool get isWorkspace => workspaceId != null && tabScope == null;
  bool get isTab => tabScope != null;

  @override
  List<Object?> get props => [workspaceId, tabScope, sessionId];
}
