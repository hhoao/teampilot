import '../l10n/app_localizations.dart';

/// Coarse relative labels: just now → minutes → hours → days (no exact dates).
String formatCoarseRelativeTime(
  AppLocalizations l10n,
  DateTime time, {
  DateTime? now,
}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return l10n.notificationTimeJustNow;
  if (diff.inHours < 1) {
    return l10n.notificationTimeMinutesAgo(diff.inMinutes);
  }
  if (diff.inDays < 1) {
    return l10n.notificationTimeHoursAgo(diff.inHours);
  }
  return l10n.notificationTimeDaysAgo(diff.inDays);
}
