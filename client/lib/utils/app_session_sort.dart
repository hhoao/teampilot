import '../models/app_session.dart';

enum AppSessionSort {
  recentlyUpdated,
  createdDesc,
}

List<AppSession> sortAppSessions(
  List<AppSession> sessions, {
  required AppSessionSort sort,
}) {
  final sorted = List<AppSession>.from(sessions);
  sorted.sort((a, b) {
    // Pinned always first.
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    // Then by sort criteria.
    return switch (sort) {
      AppSessionSort.recentlyUpdated => _byUpdatedAt(a, b),
      AppSessionSort.createdDesc => b.createdAt.compareTo(a.createdAt),
    };
  });
  return sorted;
}

int _byUpdatedAt(AppSession a, AppSession b) {
  final au = a.updatedAt != 0 ? a.updatedAt : a.createdAt;
  final bu = b.updatedAt != 0 ? b.updatedAt : b.createdAt;
  return bu.compareTo(au);
}
