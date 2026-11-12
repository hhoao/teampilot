import 'dart:convert';

import '../models/ssh_server_profile.dart';
import '../services/io/filesystem.dart';
import '../services/storage/home_storage.dart';
import '../services/storage/storage_failure.dart';
import '../utils/logging/logger.dart';

/// Remote-side catalog of SSH server configurations.
///
/// Reads and writes through the injected [HomeStorage], so the catalog lives on
/// whichever machine is the current home plane: pairing a new device against
/// the same home makes every server configuration available there. Credentials
/// are never part of a profile — see [SshServerProfile].
///
/// The catalog of SSH servers configured on the home plane, stored in a single
/// file: `<home>/ssh_profiles/profiles.json`.
///
/// It is fully independent of the device-local `remote-targets.json` that
/// backs "Remote connections": nothing is copied between the two, and servers
/// here are created and edited on this page. Keeping the catalogs separate is
/// what lets each page own its own entries instead of mirroring the other.
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

  Future<List<SshServerProfile>> loadAll() async {
    final profiles = await _loadProjected();
    final sorted = profiles.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(sorted);
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
