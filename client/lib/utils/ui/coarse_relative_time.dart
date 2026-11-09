import '../../l10n/app_localizations.dart';

/// Coarse relative labels: just now → minutes → hours → days (no exact dates).
String formatCoarseRelativeTime(
  AppLocalizations l10n,
  DateTime time, {
  DateTime? now,
}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return l10n.notification.timeJustNow;
  if (diff.inHours < 1) {
    return l10n.notification.timeMinutesAgo(minutes: diff.inMinutes);
  }
  if (diff.inDays < 1) {
    return l10n.notification.timeHoursAgo(hours: diff.inHours);
  }
  return l10n.notification.timeDaysAgo(days: diff.inDays);
}
