import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Disk read + JSON decode for derived index snapshots off the UI isolate.
///
/// Top-level parsers only — no model imports so [Isolate.run] stays valid.
abstract final class IndexSnapshotIsolate {
  IndexSnapshotIsolate._();

  static const workspacesIndexVersion = 1;
  static const launchProfilesIndexVersion = 1;

  static Future<List<Map<String, Object?>>?> readWorkspacesMaps(
    String indexPath,
  ) {
    return Isolate.run(() => _readWorkspacesMaps(indexPath));
  }

  static Future<List<Map<String, Object?>>?> readLaunchProfileMaps(
    String indexPath,
  ) {
    return Isolate.run(() => _readLaunchProfileMaps(indexPath));
  }
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
