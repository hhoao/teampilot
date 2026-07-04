import '../../models/automation.dart';

/// Session binding policy for [AutomationAction.launchPrompt] automations.
///
/// Scheduled messages always require a fixed [Automation.sessionId].
/// Launch prompts may lazily bind a session on first successful dispatch when
/// [Automation.reuseSession] is enabled.
class AutomationLaunchSessionBinding {
  AutomationLaunchSessionBinding._();

  /// Whether this launch-prompt automation is bound to a reusable session.
  static bool hasBinding(Automation automation) {
    final id = automation.sessionId?.trim() ?? '';
    return automation.isLaunchPrompt && automation.reuseSession && id.isNotEmpty;
  }

  /// Persists or clears the bound session after a successful delivery.
  static Automation applyAfterSuccessfulDispatch(
    Automation automation, {
    required String sessionId,
  }) {
    if (!automation.isLaunchPrompt) return automation;
    final trimmed = sessionId.trim();
    if (trimmed.isEmpty) return automation;

    if (automation.reuseSession) {
      return automation.copyWith(sessionId: trimmed);
    }
    if ((automation.sessionId?.trim().isNotEmpty ?? false)) {
      return automation.copyWith(clearSessionId: true);
    }
    return automation;
  }

  /// Editor save: drop a stale binding when reuse is turned off.
  static Automation stripWhenReuseDisabled(Automation automation) {
    if (!automation.isLaunchPrompt || automation.reuseSession) {
      return automation;
    }
    if (automation.sessionId == null || automation.sessionId!.trim().isEmpty) {
      return automation;
    }
    return automation.copyWith(clearSessionId: true);
  }

  /// When a bound session is deleted from the workspace.
  static Automation onBoundSessionRemoved(Automation automation) {
    final bound = automation.sessionId?.trim() ?? '';
    if (bound.isEmpty) return automation;

    if (automation.isScheduledMessage) {
      if (!automation.enabled) return automation;
      return automation.copyWith(
        enabled: false,
        clearNextRunAtMs: true,
      );
    }
    if (automation.isLaunchPrompt && automation.reuseSession) {
      return automation.copyWith(clearSessionId: true);
    }
    return automation;
  }
}
