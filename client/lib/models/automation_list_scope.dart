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
  const AutomationListScope.workspace(String workspaceId)
    : this._(workspaceId: workspaceId.trim());

  /// One launch-profile store, optionally narrowed to [sessionId].
  const AutomationListScope.tab(AutomationTabScope tabScope, {String? sessionId})
    : this._(tabScope: tabScope, sessionId: sessionId?.trim());

  final String? workspaceId;
  final AutomationTabScope? tabScope;
  final String? sessionId;

  bool get isAll => workspaceId == null && tabScope == null;
  bool get isWorkspace => workspaceId != null && tabScope == null;
  bool get isTab => tabScope != null;

  List<AutomationListScope> get reloadTargets {
    if (isTab) return [this];
    if (isWorkspace) return [this];
    return const [AutomationListScope.all()];
  }

  @override
  List<Object?> get props => [workspaceId, tabScope, sessionId];
}
