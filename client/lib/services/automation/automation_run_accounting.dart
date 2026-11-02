import '../../models/automation.dart';
import 'automation_schedule_calculator.dart';

/// Advances an automation after a run finishes: counts the run, stamps it,
/// and resolves the next occurrence (or disables on limit expiry).
class AutomationRunAccounting {
  const AutomationRunAccounting(this._scheduleCalculator);

  final AutomationScheduleCalculator _scheduleCalculator;

  Automation advance({
    required Automation automation,
    required int lastRunAtMs,
    required int nowMs,
  }) {
    final nextRunCount = automation.runCount + 1;
    final max = automation.effectiveMaxRunCount;
    final limitReached = max != null && nextRunCount >= max;
    final stillEnabled = automation.enabled && !limitReached;
    final nextRunAtMs = stillEnabled
        ? _scheduleCalculator.computeNextRunAtMs(
            automation,
            afterMs: lastRunAtMs,
          )
        : null;
    return automation.copyWith(
      lastRunAtMs: lastRunAtMs,
      runCount: nextRunCount,
      enabled: stillEnabled,
      nextRunAtMs: nextRunAtMs,
      clearNextRunAtMs: nextRunAtMs == null,
      updatedAtMs: nowMs,
    );
  }
}
