import 'package:intl/intl.dart';

/// Formats a chat message timestamp for the message action bar.
///
/// Same local calendar day as [now] (defaults to `DateTime.now()`) renders
/// `HH:mm`; any other day renders `MMMd HH:mm` (zh: `11月6日 15:44`,
/// en: `Nov 6 15:44`). Returns null when [createdAt] is null — callers hide
/// the label in that case.
String? formatChatTimestamp(
  DateTime? createdAt, {
  DateTime? now,
  required String locale,
}) {
  if (createdAt == null) return null;
  final local = createdAt.toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  final sameDay =
      local.year == reference.year &&
      local.month == reference.month &&
      local.day == reference.day;
  final time = DateFormat('HH:mm').format(local);
  if (sameDay) return time;
  return '${DateFormat('MMMd', locale).format(local)} $time';
}
