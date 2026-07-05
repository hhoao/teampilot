import '../../models/automation.dart';

/// Aggregate stats for every automation under a workspace.
class AutomationWorkspaceSummary {
  const AutomationWorkspaceSummary({
    required this.enabledCount,
    this.nearestNextRunAtMs,
  });

  final int enabledCount;
  final int? nearestNextRunAtMs;

  static AutomationWorkspaceSummary fromAutomations(
    List<Automation> automations,
    String workspaceId,
  ) {
    final enabled = automations
        .where((a) => a.workspaceId == workspaceId && a.enabled)
        .toList();
    int? nearest;
    for (final automation in enabled) {
      final next = automation.nextRunAtMs;
      if (next == null) continue;
      if (nearest == null || next < nearest) nearest = next;
    }
    return AutomationWorkspaceSummary(
      enabledCount: enabled.length,
      nearestNextRunAtMs: nearest,
    );
  }
}
