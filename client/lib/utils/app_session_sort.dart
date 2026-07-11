import '../models/app_session.dart';

enum AppSessionSort {
  /// Drag-induced arrangement ([AppSession.sortOrder]). Not shown in the sort
  /// menu — entered automatically when the user reorders, left when they pick
  /// a time-based mode again.
  manual,
  recentlyUpdated,
  createdDesc;

  /// Default for the workspace conversation sidebar (not persisted).
  static const AppSessionSort sidebarDefault = AppSessionSort.recentlyUpdated;

  /// Choices exposed in the sidebar sort menu (excludes [manual]).
  static const List<AppSessionSort> menuValues = [
    AppSessionSort.recentlyUpdated,
    AppSessionSort.createdDesc,
  ];
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
      AppSessionSort.manual => _byManualOrder(a, b),
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

/// Ascending [AppSession.sortOrder] (lower = higher in the list); never-stamped
/// rows (`sortOrder == 0`) fall back to recently-updated so the list matches the
/// trailing activity timestamps until the user drags something.
int _byManualOrder(AppSession a, AppSession b) {
  if (a.sortOrder != b.sortOrder) return a.sortOrder.compareTo(b.sortOrder);
  return _byUpdatedAt(a, b);
}
