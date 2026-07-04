import '../../l10n/app_localizations.dart';
import '../../models/automation.dart';

enum AutomationSort {
  nameAsc,
  nameDesc,
  nextRunAsc,
  recentlyUpdated,
}

extension AutomationSortLabels on AutomationSort {
  String label(AppLocalizations l10n) => switch (this) {
        AutomationSort.nameAsc => l10n.automationsSortNameAsc,
        AutomationSort.nameDesc => l10n.automationsSortNameDesc,
        AutomationSort.nextRunAsc => l10n.automationsSortNextRun,
        AutomationSort.recentlyUpdated => l10n.automationsSortRecentlyUpdated,
      };
}

enum AutomationEnabledFilter { all, enabledOnly, disabledOnly }

enum AutomationActionFilter { all, scheduledMessage, launchPrompt }

List<Automation> sortAutomations(
  List<Automation> automations,
  AutomationSort sort,
) {
  final sorted = List<Automation>.from(automations);
  sorted.sort((a, b) {
    return switch (sort) {
      AutomationSort.nameAsc =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      AutomationSort.nameDesc =>
        b.name.toLowerCase().compareTo(a.name.toLowerCase()),
      AutomationSort.nextRunAsc => _compareNextRun(a, b),
      AutomationSort.recentlyUpdated => b.updatedAtMs.compareTo(a.updatedAtMs),
    };
  });
  return sorted;
}

int _compareNextRun(Automation a, Automation b) {
  final an = a.nextRunAtMs;
  final bn = b.nextRunAtMs;
  if (an == null && bn == null) return 0;
  if (an == null) return 1;
  if (bn == null) return -1;
  return an.compareTo(bn);
}

List<Automation> filterAutomations({
  required List<Automation> automations,
  AutomationEnabledFilter enabledFilter = AutomationEnabledFilter.all,
  AutomationActionFilter actionFilter = AutomationActionFilter.all,
  String? sessionId,
}) {
  Iterable<Automation> items = automations;
  if (sessionId != null) {
    items = items.where((a) => a.sessionId == sessionId);
  }
  items = switch (enabledFilter) {
    AutomationEnabledFilter.all => items,
    AutomationEnabledFilter.enabledOnly => items.where((a) => a.enabled),
    AutomationEnabledFilter.disabledOnly => items.where((a) => !a.enabled),
  };
  items = switch (actionFilter) {
    AutomationActionFilter.all => items,
    AutomationActionFilter.scheduledMessage =>
      items.where((a) => a.isScheduledMessage),
    AutomationActionFilter.launchPrompt =>
      items.where((a) => !a.isScheduledMessage),
  };
  return items.toList(growable: false);
}
