import 'package:equatable/equatable.dart';

import '../models/automation.dart';
import '../models/automation_tab_scope.dart';

enum AutomationLoadStatus { idle, loading, ready, error }

class AutomationState extends Equatable {
  const AutomationState({
    this.automations = const [],
    this.runsByAutomationId = const {},
    this.status = AutomationLoadStatus.idle,
    this.errorMessage,
    this.filterTabScope,
    this.filterSessionId,
  });

  final List<Automation> automations;
  final Map<String, List<AutomationRun>> runsByAutomationId;
  final AutomationLoadStatus status;
  final String? errorMessage;
  final AutomationTabScope? filterTabScope;
  final String? filterSessionId;

  List<Automation> get visibleAutomations {
    var items = automations;
    final scope = filterTabScope;
    if (scope != null) {
      items = items
          .where(
            (a) =>
                a.workspaceId == scope.workspaceId &&
                a.launchProfileId == scope.launchProfileId,
          )
          .toList();
    }
    final sessionId = filterSessionId?.trim();
    if (sessionId != null && sessionId.isNotEmpty) {
      items = items.where((a) => a.sessionId == sessionId).toList();
    }
    return items;
  }

  AutomationState copyWith({
    List<Automation>? automations,
    Map<String, List<AutomationRun>>? runsByAutomationId,
    AutomationLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    AutomationTabScope? filterTabScope,
    bool clearFilterTabScope = false,
    String? filterSessionId,
    bool clearFilterSessionId = false,
  }) {
    return AutomationState(
      automations: automations ?? this.automations,
      runsByAutomationId: runsByAutomationId ?? this.runsByAutomationId,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      filterTabScope: clearFilterTabScope
          ? null
          : (filterTabScope ?? this.filterTabScope),
      filterSessionId: clearFilterSessionId
          ? null
          : (filterSessionId ?? this.filterSessionId),
    );
  }

  @override
  List<Object?> get props => [
    automations,
    runsByAutomationId,
    status,
    errorMessage,
    filterTabScope,
    filterSessionId,
  ];
}
