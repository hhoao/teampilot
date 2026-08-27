import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// Disk read + JSON decode for derived index snapshots off the UI isolate.
///
/// Top-level parsers only — no model imports so [Isolate.run] stays valid.
///
/// Optional [Isolate.run] readers exist for large snapshots, but boot and
/// mutation paths must read on the calling isolate — cold-start `Isolate.run`
/// can hang on debug and leave the boot splash stuck.
abstract final class IndexSnapshotIsolate {
  IndexSnapshotIsolate._();

  static const workspacesIndexVersion = 1;
  static const launchProfilesIndexVersion = 1;

  /// Test seam: when set, [readWorkspacesMaps] uses this instead of [Isolate.run].
  @visibleForTesting
  static Future<List<Map<String, Object?>>?> Function(String indexPath)?
  debugWorkspacesReaderOverride;

  /// Test seam: when set, [readLaunchProfileMaps] uses this instead of [Isolate.run].
  @visibleForTesting
  static Future<List<Map<String, Object?>>?> Function(String indexPath)?
  debugLaunchProfilesReaderOverride;

  static Future<List<Map<String, Object?>>?> readWorkspacesMaps(
    String indexPath,
  ) {
    final override = debugWorkspacesReaderOverride;
    if (override != null) return override(indexPath);
    return Isolate.run(
      () => _readWorkspacesMaps(indexPath),
      debugName: 'index-workspaces-reader',
    );
  }

  static Future<List<Map<String, Object?>>?> readLaunchProfileMaps(
    String indexPath,
  ) {
    final override = debugLaunchProfilesReaderOverride;
    if (override != null) return override(indexPath);
    return Isolate.run(
      () => _readLaunchProfileMaps(indexPath),
      debugName: 'index-launch-profiles-reader',
    );
  }

  /// Same parse as the isolate path, but on the calling isolate (mutation-safe).
  static List<Map<String, Object?>>? readWorkspacesMapsSync(String indexPath) =>
      _readWorkspacesMaps(indexPath);

  /// Same parse as the isolate path, but on the calling isolate (mutation-safe).
  static List<Map<String, Object?>>? readLaunchProfileMapsSync(
    String indexPath,
  ) => _readLaunchProfileMaps(indexPath);
}

List<Map<String, Object?>>? _readWorkspacesMaps(String indexPath) {
  final raw = _readUtf8File(indexPath);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    if (decoded['version'] != IndexSnapshotIsolate.workspacesIndexVersion) {
      return null;
    }
    final list = decoded['workspaces'];
    if (list is! List) return null;
    final out = <Map<String, Object?>>[];
    for (final item in list) {
      if (item is! Map) return null;
      final map = Map<String, Object?>.from(item);
      final id = map['workspaceId'];
      if (id is! String || id.trim().isEmpty) return null;
      out.add(map);
    }
    return out;
  } on Object {
    return null;
  }
}

List<Map<String, Object?>>? _readLaunchProfileMaps(String indexPath) {
  final raw = _readUtf8File(indexPath);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    if (decoded['version'] != IndexSnapshotIsolate.launchProfilesIndexVersion) {
      return null;
    }
    final list = decoded['profiles'];
    if (list is! List) return null;
    final out = <Map<String, Object?>>[];
    for (final item in list) {
      if (item is! Map) return null;
      final map = Map<String, Object?>.from(item);
      final id = map['id'];
      if (id is! String || id.trim().isEmpty) return null;
      out.add(map);
    }
    return out;
  } on Object {
    return null;
  }
}

String? _readUtf8File(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final raw = file.readAsStringSync();
  if (raw.isEmpty) return null;
  return raw;
}
