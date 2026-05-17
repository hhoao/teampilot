import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/ssh_profile.dart';
import '../services/app_storage.dart';

class SshProfileRepository {
  SshProfileRepository({String? rootDir})
      : _root = rootDir ?? p.join(AppStorage.basePath, 'ssh_profiles');

  final String _root;

  String get _profilesFile => p.join(_root, 'profiles.json');

  String get _selectedProfileFile => p.join(_root, 'selected_profile.txt');

  Future<List<SshProfile>> loadAll() async {
    final file = File(_profilesFile);
    if (!await file.exists()) return [];
    try {
      final json = jsonDecode(await file.readAsString());
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
    final dir = Directory(_root);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final jsonList = profiles.map((p) => p.toJson()).toList();
    final file = File(_profilesFile);
    final tmp = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsString(jsonEncode(jsonList));
    await tmp.rename(file.path);
  }

  Future<String> loadSelectedProfileId() async {
    final file = File(_selectedProfileFile);
    if (!await file.exists()) return '';
    try {
      return (await file.readAsString()).trim();
    } on Object {
      return '';
    }
  }

  Future<void> saveSelectedProfileId(String profileId) async {
    final dir = Directory(_root);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(_selectedProfileFile);
    if (profileId.trim().isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    final tmp = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsString(profileId.trim());
    await tmp.rename(file.path);
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
