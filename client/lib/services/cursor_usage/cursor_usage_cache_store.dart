import 'dart:convert';

import '../../models/cursor_usage_report.dart';
import '../io/filesystem.dart';

final class CursorUsageCacheStore {
  CursorUsageCacheStore({
    required Filesystem fs,
    required String Function(String accountId) pathFor,
  }) : _fs = fs,
       _pathFor = pathFor;

  final Filesystem _fs;
  final String Function(String accountId) _pathFor;

  Future<CursorUsageCache> load(String accountId) async {
    final raw = await _fs.readString(_pathFor(accountId));
    if (raw == null || raw.trim().isEmpty) {
      return CursorUsageCache(accountId: accountId);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return CursorUsageCache(accountId: accountId);
      return CursorUsageCache.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return CursorUsageCache(accountId: accountId);
    }
  }

  Future<void> save(CursorUsageCache cache) async {
    final path = _pathFor(cache.accountId);
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(cache.toJson()),
    );
  }
}
