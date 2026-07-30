import '../../models/progress_activity.dart';

/// Display fraction for progress UI: explicit [ProgressActivity.fraction] first,
/// then item counts, then byte counts, else indeterminate (`null`).
double? resolveProgressFraction(ProgressActivity activity) {
  final fraction = activity.fraction;
  if (fraction != null) {
    return fraction;
  }

  final totalItems = activity.totalItems;
  if (totalItems != null && totalItems > 0) {
    return (activity.completedItems ?? 0) / totalItems;
  }

  final bytesTotal = activity.bytesTotal;
  if (bytesTotal != null && bytesTotal > 0) {
    return (activity.bytesDone ?? 0) / bytesTotal;
  }

  return null;
}
