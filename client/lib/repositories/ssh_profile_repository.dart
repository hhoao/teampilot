import 'dart:convert';

import '../models/ssh_profile.dart';
import '../services/storage/home_storage.dart';
import '../services/io/filesystem.dart';
import '../services/storage/storage_failure.dart';

class SshProfileRepository {
  /// Defaults follow the home control plane ([storage], test convenience).
  /// Production must use [deviceLocalSshProfileRepository] so the catalog
  /// stays on-device when home is rebound to SSH.
  SshProfileRepository({
    String? rootDir,
    Filesystem? fs,
    required HomeStorage storage,
  }) : _rootDirOverride = rootDir,
      _fsOverride = fs,
      _storage = storage;

  final String? _rootDirOverride;
  final Filesystem? _fsOverride;
  final HomeStorage _storage;

  String get _root => _rootDirOverride ?? _storage.paths.sshProfilesDir;

  Filesystem get _fs => _fsOverride ?? _storage.fs;

  String get _profilesFile => _fs.pathContext.join(_root, 'profiles.json');

  String get _selectedProfileFile =>
      _fs.pathContext.join(_root, 'selected_profile.txt');

  Future<List<SshProfile>> loadAll() async {
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

  Future<void> saveAll(List<SshProfile> profiles) async {
    await _fs.ensureDir(_root);
    final jsonList = profiles.map((p) => p.toJson()).toList();
    await _fs.atomicWrite(_profilesFile, jsonEncode(jsonList));
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

  Future<void> save(SshProfile profile) async {
    final profiles = await loadAll();
    final idx = profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      profiles[idx] = profile;
    } else {
      profiles.add(profile);
    }
    await saveAll(profiles);
  }

  Future<void> delete(String profileId) async {
    final profiles = await loadAll();
    profiles.removeWhere((p) => p.id == profileId);
    await saveAll(profiles);
  }

  Future<SshProfile?> findById(String profileId) async {
    final profiles = await loadAll();
    try {
      return profiles.firstWhere((p) => p.id == profileId);
    } on StateError {
      return null;
    }
  }
}
