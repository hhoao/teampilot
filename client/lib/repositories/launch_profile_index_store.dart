import 'dart:convert';

import '../models/launch_profile.dart';
import '../models/launch_profile_kind.dart';
import '../models/personal_profile.dart';
import '../models/team_config.dart';
import '../services/io/filesystem.dart';
import '../services/io/local_filesystem.dart';
import '../utils/logger.dart';
import 'index_snapshot_isolate.dart';

/// Derived snapshot of launch profile records for fast startup load.
///
/// Per-profile [profile.json] files remain source of truth; this file is
/// updated on every repository mutation.
class LaunchProfileIndexStore {
  LaunchProfileIndexStore({
    required this.launchProfilesDir,
    required this.fs,
  });

  final String launchProfilesDir;
  final Filesystem fs;

  static const indexVersion = 1;

  String get _indexFile =>
      fs.pathContext.join(fs.pathContext.dirname(launchProfilesDir), 'launch-profiles-index.json');

  static LaunchProfile decodeProfile(Map<String, Object?> json) {
    return switch (LaunchProfileKind.decode(json['kind'])) {
      LaunchProfileKind.personal => PersonalProfile.fromJson(json),
      LaunchProfileKind.team => TeamProfile.fromJson(json),
    };
  }

  Future<List<LaunchProfile>?> tryRead() async {
    final indexFile = _indexFile;
    if (fs is LocalFilesystem) {
      try {
        final maps = await IndexSnapshotIsolate.readLaunchProfileMaps(indexFile);
        final profiles = _profilesFromMaps(maps);
        if (profiles != null) {
          appLogger.i('[boot] launch-profiles-index read via isolate');
          return profiles;
        }
      } on Object {
        // Fall back to filesystem abstraction (WSL / SSH).
      }
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
      final profile = decodeProfile(item);
      if (profile.id.trim().isEmpty) return null;
      profiles.add(profile);
    }
    return profiles;
  }

  Future<void> writeAll(List<LaunchProfile> profiles) async {
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

  Future<void> upsert(LaunchProfile profile) async {
    final current = await tryRead() ?? <LaunchProfile>[];
    final id = profile.id.trim();
    final next = <LaunchProfile>[
      for (final existing in current)
        if (existing.id != id) existing,
      profile,
    ];
    await writeAll(next);
  }

  Future<void> remove(String profileId) async {
    final trimmed = profileId.trim();
    if (trimmed.isEmpty) return;
    final current = await tryRead();
    if (current == null) return;
    final next = current
        .where((profile) => profile.id != trimmed)
        .toList(growable: false);
    if (next.length == current.length) return;
    await writeAll(next);
  }
}
