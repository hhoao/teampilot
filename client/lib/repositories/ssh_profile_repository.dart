import 'dart:convert';

import '../models/connection/machine_id.dart';
import '../models/ssh_profile.dart';
import '../repositories/connection_store.dart';
import '../services/connect/profile_connection_mapping.dart';
import '../services/io/filesystem.dart';
import '../services/storage/home_storage.dart';
import '../services/storage/storage_failure.dart';

/// Runtime view over the device's connections.
///
/// Production always injects a [ConnectionStore]; the legacy `profiles.json`
/// mode only remains for tests that need a bare catalog.
class SshProfileRepository {
  SshProfileRepository({
    ConnectionStore? connections,
    String? rootDir,
    Filesystem? fs,
    required HomeStorage storage,
  }) : _connections = connections,
       _rootDirOverride = rootDir,
       _fsOverride = fs,
       _storage = storage;

  final ConnectionStore? _connections;
  final String? _rootDirOverride;
  final Filesystem? _fsOverride;
  final HomeStorage _storage;

  /// The injected device-local connection catalog.
  ConnectionStore get connectionStore {
    final connections = _connections;
    if (connections == null) {
      throw StateError(
        'SshProfileRepository.connectionStore is unavailable in legacy '
        'profiles.json mode: inject a ConnectionStore.',
      );
    }
    return connections;
  }

  String get _root => _rootDirOverride ?? _storage.paths.sshProfilesDir;

  Filesystem get _fs => _fsOverride ?? _storage.fs;

  String get _profilesFile => _fs.pathContext.join(_root, 'profiles.json');

  String get _selectedProfileFile =>
      _fs.pathContext.join(_root, 'selected_profile.txt');

  Future<List<SshProfile>> loadAll() async {
    final connections = _connections;
    if (connections != null) {
      final rows = await connections.loadAll();
      return rows.map(profileFromConnection).toList();
    }
    return _loadAllLegacy();
  }

  Future<void> save(SshProfile profile) async {
    final connections = _connections;
    if (connections != null) {
      await _saveConnection(connections, profile);
      return;
    }
    final profiles = await _loadAllLegacy();
    final idx = profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      profiles[idx] = profile;
    } else {
      profiles.add(profile);
    }
    await _saveAllLegacy(profiles);
  }

  Future<void> saveAll(List<SshProfile> profiles) async {
    if (_connections != null) {
      for (final profile in profiles) {
        await save(profile);
      }
      return;
    }
    await _saveAllLegacy(profiles);
  }

  Future<void> delete(String profileId) async {
    final connections = _connections;
    if (connections != null) {
      await connections.delete(MachineId(profileId));
      return;
    }
    final profiles = await _loadAllLegacy();
    profiles.removeWhere((p) => p.id == profileId);
    await _saveAllLegacy(profiles);
  }

  Future<SshProfile?> findById(String profileId) async {
    final connections = _connections;
    if (connections != null) {
      final connection = await connections.findById(MachineId(profileId));
      return connection == null ? null : profileFromConnection(connection);
    }
    final profiles = await _loadAllLegacy();
    try {
      return profiles.firstWhere((p) => p.id == profileId);
    } on StateError {
      return null;
    }
  }

  Future<String> loadSelectedProfileId() async {
    if (!(await _fs.stat(_selectedProfileFile)).isFile) return '';
    try {
      return (await _fs.readString(_selectedProfileFile))?.trim() ?? '';
    } on Object catch (error) {
      if (isStorageTransportFailure(error)) rethrow;
      return '';
    }
  }

  Future<void> saveSelectedProfileId(String profileId) async {
    await _fs.ensureDir(_root);
    if (profileId.trim().isEmpty) {
      if ((await _fs.stat(_selectedProfileFile)).exists) {
        await _fs.removeRecursive(_selectedProfileFile);
      }
      return;
    }
    await _fs.atomicWrite(_selectedProfileFile, profileId.trim());
  }

  /// Write path for both dial-plan fields (address set, account, trust pins,
  /// credential reference) and local-only state (path cache, display name,
  /// last-good preference). Only the former can change the plan generation.
  Future<void> _saveConnection(
    ConnectionStore connections,
    SshProfile profile,
  ) async {
    final previous = await connections.findById(MachineId(profile.id));
    await connections.save(
      connectionFromProfile(
        profile,
        previous: previous,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  // ---- legacy `profiles.json` path, test-only ----

  Future<List<SshProfile>> _loadAllLegacy() async {
    if (!(await _fs.stat(_profilesFile)).isFile) return [];
    try {
      final raw = await _fs.readString(_profilesFile);
      if (raw == null || raw.isEmpty) return [];
      final json = jsonDecode(raw);
      if (json is List) {
        return json
            .whereType<Map<String, Object?>>()
            .map((e) => SshProfile.fromJson(e))
            .toList();
      }
    } on Object catch (error) {
      // A dropped transport must not read as "no profiles stored": the user
      // would lose every SSH profile on a flaky connection.
      if (isStorageTransportFailure(error)) rethrow;
    }
    return [];
  }

  Future<void> _saveAllLegacy(List<SshProfile> profiles) async {
    await _fs.ensureDir(_root);
    final jsonList = profiles.map((p) => p.toJson()).toList();
    await _fs.atomicWrite(_profilesFile, jsonEncode(jsonList));
  }
}
