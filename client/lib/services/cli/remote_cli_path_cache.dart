import 'dart:convert';

import 'package:logger/logger.dart';

import '../../models/team_config.dart';
import '../io/filesystem.dart';

/// Device-local cache of remote CLI executable paths keyed by SSH profile id.
///
/// Discovery probes run several shells per CLI over SSH (~seconds); the cache
/// lets boot apply the last-known paths instantly and refresh in the
/// background. Storage must be device-local (native app data), never under the
/// possibly-remote home filesystem. Corrupt or missing data degrades to an
/// empty map — every method is safe to call without try/catch.
class RemoteCliPathCache {
  RemoteCliPathCache({required Filesystem fs, required this.filePath})
    : _fs = fs;

  final String filePath;
  final Filesystem _fs;

  /// Cached paths for [profileId]; empty when absent, empty-valued, or corrupt.
  Future<Map<CliTool, String>> load(String profileId) async {
    try {
      final raw = await _fs.readString(filePath);
      if (raw == null || raw.isEmpty) return const {};
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return const {};
      final entry = json[profileId];
      if (entry is! Map<String, Object?>) return const {};
      return {
        for (final e in entry.entries)
          if (CliTool.tryParse(e.key) != null && e.value is String)
            CliTool.tryParse(e.key)!: e.value as String,
      };
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Remote CLI path cache read failed for $profileId',
        error: error,
        stackTrace: stackTrace,
      );
      return const {};
    }
  }

  /// Persists [paths] for [profileId], preserving other profiles' entries.
  Future<void> save(String profileId, Map<CliTool, String> paths) async {
    try {
      final json = await _readAll();
      json[profileId] = {
        for (final e in paths.entries) e.key.value: e.value,
      };
      await _fs.atomicWrite(filePath, jsonEncode(json));
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Remote CLI path cache write failed for $profileId',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Drops the cached entry for [profileId] (connection identity changed).
  Future<void> invalidate(String profileId) async {
    try {
      final json = await _readAll();
      if (json.remove(profileId) == null) return;
      await _fs.atomicWrite(filePath, jsonEncode(json));
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Remote CLI path cache invalidate failed for $profileId',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Map<String, Object?>> _readAll() async {
    final raw = await _fs.readString(filePath);
    if (raw == null || raw.isEmpty) return {};
    final json = jsonDecode(raw);
    if (json is! Map<String, Object?>) return {};
    return {
      for (final e in json.entries)
        if (e.value is Map<String, Object?>) e.key: e.value,
    };
  }
}
