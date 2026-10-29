import '../usage/usage_format.dart';

/// `report.totalCents` is USD cents; the shared formatter wants micro-USD.
String formatCursorUsageUsd(double cents) =>
    formatUsageCost((cents * 10000).round());

String formatCursorUsageDate(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String formatCursorUsageTimestamp(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${formatCursorUsageDate(ms)} $hour:$minute';
}
