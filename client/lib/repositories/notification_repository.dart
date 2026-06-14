import 'dart:convert';

import '../models/app_notification.dart';
import '../services/io/filesystem.dart';
import '../theme/app_toast_theme.dart';
import '../utils/logger.dart';

const notificationMaxItems = 50;
const notificationMaxAge = Duration(days: 7);

/// Persists app notifications at `{teampilotRoot}/notifications.json`.
class NotificationRepository {
  NotificationRepository({
    Filesystem? fs,
    String? storePath,
    DateTime Function()? clock,
  })  : _fs = fs,
        _storePath = storePath,
        _clock = clock ?? DateTime.now;

  final Filesystem? _fs;
  final String? _storePath;
  final DateTime Function() _clock;

  AppNotificationStore _cache = const AppNotificationStore();
  bool _hydrated = false;

  Future<AppNotificationStore> load({bool forceReload = false}) async {
    if (!forceReload && _hydrated) return _cache;
    final fs = _fs;
    final path = _storePath;
    if (fs == null || path == null) return _cache;

    final stat = await fs.stat(path);
    if (!stat.exists) {
      _hydrated = true;
      return _cache = const AppNotificationStore();
    }
    final raw = await fs.readString(path);
    if (raw == null || raw.trim().isEmpty) {
      _hydrated = true;
      return _cache = const AppNotificationStore();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _hydrated = true;
        return _cache = AppNotificationStore.fromJson(
          decoded.cast<String, Object?>(),
        );
      }
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[notifications] corrupt store, resetting',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _hydrated = true;
    return _cache = const AppNotificationStore();
  }

  Future<AppNotificationStore> append({
    required String id,
    required String message,
    required AppToastVariant variant,
  }) async {
    if (variant == AppToastVariant.info) {
      return _cache;
    }
    final now = _clock();
    final next = AppNotification(
      id: id,
      variant: variant,
      message: message,
      createdAt: now,
    );
    final pruned = _prune([next, ..._cache.items], now: now);
    return save(AppNotificationStore(items: pruned));
  }

  Future<AppNotificationStore> save(AppNotificationStore store) async {
    final pruned = _prune(store.items, now: _clock());
    _cache = store.copyWith(items: pruned);
    final fs = _fs;
    final path = _storePath;
    if (fs == null || path == null) return _cache;

    try {
      final dir = fs.pathContext.dirname(path);
      await fs.ensureDir(dir);
      await fs.atomicWrite(
        path,
        const JsonEncoder.withIndent('  ').convert(_cache.toJson()),
      );
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[notifications] save failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return _cache;
  }

  Future<AppNotificationStore> markRead(String id) async {
    final items = [
      for (final item in _cache.items)
        if (item.id == id) item.copyWith(isRead: true) else item,
    ];
    return save(_cache.copyWith(items: items));
  }

  Future<AppNotificationStore> markAllRead() async {
    final items = [
      for (final item in _cache.items) item.copyWith(isRead: true),
    ];
    return save(_cache.copyWith(items: items));
  }

  Future<AppNotificationStore> delete(String id) async {
    final items = _cache.items.where((item) => item.id != id).toList();
    return save(_cache.copyWith(items: items));
  }

  Future<AppNotificationStore> clearAll() async {
    return save(const AppNotificationStore());
  }

  List<AppNotification> _prune(
    List<AppNotification> items, {
    required DateTime now,
  }) {
    final cutoff = now.subtract(notificationMaxAge);
    final filtered = [
      for (final item in items)
        if (!item.createdAt.isBefore(cutoff)) item,
    ];
  filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (filtered.length <= notificationMaxItems) return filtered;
    return filtered.take(notificationMaxItems).toList();
  }
}
