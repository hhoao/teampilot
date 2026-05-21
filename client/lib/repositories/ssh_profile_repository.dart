import 'dart:convert';

import '../models/ssh_profile.dart';
import '../services/app_storage.dart';
import '../services/io/filesystem.dart';

class SshProfileRepository {
  SshProfileRepository({String? rootDir, Filesystem? fs})
    : _rootDirOverride = rootDir,
      _fsOverride = fs;

  final String? _rootDirOverride;
  final Filesystem? _fsOverride;

  String get _root => _rootDirOverride ?? AppStorage.paths.sshProfilesDir;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

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
    } on Object {
      // ignore
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
    } on Object {
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
