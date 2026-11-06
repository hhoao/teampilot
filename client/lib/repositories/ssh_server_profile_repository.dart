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
/// Constraint: this writes `<sshProfilesDir>/profiles.json`, the same file the
/// existing `SshProfileRepository` writes when the home plane is local. Do not
/// wire this class as a second live writer to that file until
/// `SshProfileRepository` becomes the single facade over it: this repository
/// persists only the sync-visible subset of fields, so a [save] here would
/// rewrite the array from [SshServerProfile] and drop `createdAt`, `lastHome`,
/// `lastAppDataRoot`, `endpoints`, `hostKeyFingerprints`, `lastGoodKind`, and
/// `vaultEntryId`.
class SshServerProfileRepository {
  SshServerProfileRepository({required HomeStorage storage})
    : _storage = storage;

  final HomeStorage _storage;

  Filesystem get _fs => _storage.fs;

  String get _root => _storage.paths.sshProfilesDir;

  String get _file => _fs.pathContext.join(_root, 'profiles.json');

  Future<List<SshServerProfile>> loadAll() async {
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
    final all = await loadAll();
    final idx = all.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      all[idx] = profile;
    } else {
      all.add(profile);
    }
    await saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
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
