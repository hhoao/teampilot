import 'dart:convert';

import '../models/ssh_server_profile.dart';
import '../services/io/filesystem.dart';
import '../services/storage/home_storage.dart';
import '../services/storage/storage_failure.dart';
import '../utils/logging/logger.dart';
import 'remote_target_repository.dart';

/// Remote-side catalog of SSH server configurations.
///
/// Reads and writes through the injected [HomeStorage], so the catalog lives on
/// whichever machine is the current home plane: pairing a new device against
/// the same home makes every server configuration available there. Credentials
/// are never part of a profile — see [SshServerProfile].
///
/// A home plane stores its configured servers in *two* files:
///
/// * `<home>/remote-targets.json` — the catalog written by the TeamPilot app
///   running on that machine (the servers a person configured there), and
/// * `<home>/ssh_profiles/profiles.json` — the sync projection this repository
///   writes when a device connects to a target.
///
/// [loadAll] merges both, so a freshly paired home shows the servers that were
/// configured on it instead of an empty list that only waits for a push.
/// Writes stay on the projection file.
///
/// Production `SshProfileRepository` is now the single facade over the
/// device-local `remote-targets.json`; it no longer writes this file. Boot
/// migration (`migrateSshProfiles`) relocates the legacy device-local
/// `profiles.json` — which used the full `SshProfile` schema and, on a local
/// home plane, shared this exact path — to `.legacy.v1` so it cannot be parsed
/// here as ghost server profiles.
class SshServerProfileRepository {
  SshServerProfileRepository({required HomeStorage storage})
    : _storage = storage;

  final HomeStorage _storage;

  Filesystem get _fs => _storage.fs;

  String get _root => _storage.paths.sshProfilesDir;

  String get _file => _fs.pathContext.join(_root, 'profiles.json');

  /// The catalog the machine running this home plane configured for itself.
  RemoteTargetRepository get _planeTargets =>
      RemoteTargetRepository(rootDir: _storage.appDataRoot, fs: _fs);

  Future<List<SshServerProfile>> loadAll() async {
    final projected = await _loadProjected();
    final configured = await _loadConfiguredOnPlane();
    return _merge(projected: projected, configured: configured);
  }

  /// Builds the visible catalog: servers configured on this plane, overlaid by
  /// a newer synced projection entry with the same id.
  List<SshServerProfile> _merge({
    required List<SshServerProfile> projected,
    required List<SshServerProfile> configured,
  }) {
    final byId = <String, SshServerProfile>{
      for (final profile in configured) profile.id: profile,
    };
    for (final profile in projected) {
      final existing = byId[profile.id];
      if (existing == null || profile.updatedAt >= existing.updatedAt) {
        byId[profile.id] = profile;
      }
    }
    final merged = byId.values.toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return List.unmodifiable(merged);
  }

  Future<List<SshServerProfile>> _loadConfiguredOnPlane() async {
    final targets = await _planeTargets.loadAll();
    return [
      for (final target in targets)
        SshServerProfile(
          id: target.id,
          name: target.name,
          host: target.host,
          port: target.port,
          username: target.username,
          authType: target.authType,
          embeddedTarget: target.embeddedTarget,
          relayUrl: target.relayUrl,
          pairedDesktopId: target.pairedDesktopId,
          updatedAt: target.updatedAt,
        ),
    ];
  }

  Future<List<SshServerProfile>> _loadProjected() async {
    if (!(await _fs.stat(_file)).isFile) return [];
    try {
      final raw = await _fs.readString(_file);
      if (raw == null || raw.isEmpty) return [];
      final json = jsonDecode(raw);
      if (json is List) {
        return json
            .whereType<Map<String, Object?>>()
            .map(SshServerProfile.fromJson)
            .toList();
      }
    } on Object catch (error) {
      // A dropped transport must not read as "no servers stored": the caller
      // would then save an empty catalog over the user's configuration.
      if (isStorageTransportFailure(error)) rethrow;
      AppLogger.instance.w(
        '[ssh-server-profiles] unreadable catalog at $_file',
        error: error,
      );
    }
    return [];
  }

  Future<void> saveAll(List<SshServerProfile> profiles) async {
    await _fs.ensureDir(_root);
    await _fs.atomicWrite(
      _file,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> save(SshServerProfile profile) async {
    final all = await _loadProjected();
    final idx = all.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      all[idx] = profile;
    } else {
      all.add(profile);
    }
    await saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = await _loadProjected();
    all.removeWhere((p) => p.id == id);
    await saveAll(all);
  }

  Future<SshServerProfile?> findById(String id) async {
    for (final profile in await loadAll()) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}
