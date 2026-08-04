import 'dart:convert';

import 'package:synchronized/synchronized.dart';

import '../models/launch_profile.dart';
import '../models/launch_profile_kind.dart';
import '../models/team_config.dart';
import '../services/io/filesystem.dart';
import '../services/io/local_filesystem.dart';
import '../utils/logging/logger.dart';
import 'index_snapshot_isolate.dart';

/// Derived snapshot of launch profile records for fast startup load.
///
/// Per-profile [profile.json] files remain source of truth; this file is
/// updated on every repository mutation.
class LaunchProfileIndexStore {
  LaunchProfileIndexStore({required this.launchProfilesDir, required this.fs});

  final String launchProfilesDir;
  final Filesystem fs;

  /// Serializes read-modify-write so concurrent upserts do not drop entries.
  static final _mutationLocks = <String, Lock>{};

  static const indexVersion = 1;

  String get _indexFile => fs.pathContext.join(
    fs.pathContext.dirname(launchProfilesDir),
    'launch-profiles-index.json',
  );

  Lock get _mutationLock =>
      _mutationLocks.putIfAbsent(_indexFile, Lock.new);

  /// Decodes a team profile. Legacy `personal` kind records throw and must be
  /// skipped by callers.
  static LaunchProfile decodeProfile(Map<String, Object?> json) {
    switch (LaunchProfileKind.decode(json['kind'])) {
      case LaunchProfileKind.team:
        return TeamProfile.fromJson(json).normalizedLaunchConfig();
    }
  }

  /// Reads the derived index.
  ///
  /// [preferIsolate] is for cold-start prefetch only. Mutation paths must pass
  /// `false` — `Isolate.run` has hung on Linux debug during first-boot upsert.
  Future<List<LaunchProfile>?> tryRead({bool preferIsolate = true}) async {
    final indexFile = _indexFile;
    if (preferIsolate && fs is LocalFilesystem) {
      try {
        final maps = await IndexSnapshotIsolate.readLaunchProfileMaps(
          indexFile,
        );
        final profiles = _profilesFromMaps(maps);
        if (profiles != null) {
          appLogger.i('[boot] launch-profiles-index read via isolate');
          return profiles;
        }
      } on Object {
        // Fall back to filesystem abstraction (WSL / SSH).
      }
    }
    return _tryReadLocal(indexFile);
  }

  Future<List<LaunchProfile>?> _tryReadLocal(String indexFile) async {
    if (fs is LocalFilesystem) {
      final maps = IndexSnapshotIsolate.readLaunchProfileMapsSync(indexFile);
      final profiles = _profilesFromMaps(maps);
      if (profiles != null) return profiles;
    }
    final raw = await fs.readString(indexFile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['version'] != indexVersion) return null;
      final list = decoded['profiles'];
      if (list is! List) return null;
      return _profilesFromMaps([
        for (final item in list)
          if (item is Map) Map<String, Object?>.from(item),
      ]);
    } on Object {
      return null;
    }
  }

  List<LaunchProfile>? _profilesFromMaps(List<Map<String, Object?>>? maps) {
    if (maps == null) return null;
    final profiles = <LaunchProfile>[];
    for (final item in maps) {
      try {
        final profile = decodeProfile(item);
        if (profile.id.trim().isEmpty) return null;
        profiles.add(profile);
      } on FormatException {
        // Skip legacy personal / unknown kinds.
      }
    }
    return profiles;
  }

  Future<void> writeAll(List<LaunchProfile> profiles) {
    return _mutationLock.synchronized(() => _writeAllUnlocked(profiles));
  }

  Future<void> _writeAllUnlocked(List<LaunchProfile> profiles) async {
    final payload = <String, Object?>{
      'version': indexVersion,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'profiles': [for (final profile in profiles) profile.toJson()],
    };
    await fs.atomicWrite(
      _indexFile,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<void> upsert(LaunchProfile profile) {
    return _mutationLock.synchronized(() async {
      final current = await tryRead(preferIsolate: false) ?? <LaunchProfile>[];
      final id = profile.id.trim();
      final next = <LaunchProfile>[
        for (final existing in current)
          if (existing.id != id) existing,
        profile,
      ];
      await _writeAllUnlocked(next);
    });
  }

  Future<void> remove(String profileId) {
    return _mutationLock.synchronized(() async {
      final trimmed = profileId.trim();
      if (trimmed.isEmpty) return;
      final current = await tryRead(preferIsolate: false);
      if (current == null) return;
      final next = current
          .where((profile) => profile.id != trimmed)
          .toList(growable: false);
      if (next.length == current.length) return;
      await _writeAllUnlocked(next);
    });
  }
}
