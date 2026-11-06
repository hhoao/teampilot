import '../../models/automation.dart';

/// Enabled, still-schedulable automations plus their nearest next run.
class ScheduledTaskSummary {
  const ScheduledTaskSummary._({
    required this.active,
    required this.nextRunAtMs,
  });

  /// Sorted by next run ascending; items without a next run come last.
  final List<Automation> active;
  final int? nextRunAtMs;

  static ScheduledTaskSummary fromAutomations(List<Automation> automations) {
    final active = automations
        .where((a) => a.enabled && !a.isRunLimitReached)
        .toList(growable: false);

    active.sort((a, b) {
      final an = a.nextRunAtMs;
      final bn = b.nextRunAtMs;
      if (an == null && bn == null) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      if (an == null) return 1;
      if (bn == null) return -1;
      final byTime = an.compareTo(bn);
      if (byTime != 0) return byTime;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    int? nearest;
    for (final automation in active) {
      final next = automation.nextRunAtMs;
      if (next == null) continue;
      if (nearest == null || next < nearest) nearest = next;
    }

    return ScheduledTaskSummary._(
      active: List<Automation>.unmodifiable(active),
      nextRunAtMs: nearest,
    );
  }
}

/// `HH:mm` when [ms] falls on the same calendar day as [now], else
/// `yyyy-MM-dd HH:mm`.
String formatScheduledTaskNextRun(int ms, {DateTime? now}) {
  final next = DateTime.fromMillisecondsSinceEpoch(ms);
  final reference = now ?? DateTime.now();
  final hhmm =
      '${next.hour.toString().padLeft(2, '0')}:'
      '${next.minute.toString().padLeft(2, '0')}';
  final sameDay =
      next.year == reference.year &&
      next.month == reference.month &&
      next.day == reference.day;
  if (sameDay) return hhmm;
  return '${next.year.toString().padLeft(4, '0')}-'
      '${next.month.toString().padLeft(2, '0')}-'
      '${next.day.toString().padLeft(2, '0')} $hhmm';
}
