import 'dart:convert';

import '../models/project_profile.dart';
import '../models/team_config.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/storage_resolver.dart';

class _ProjectProfilePaths {
  _ProjectProfilePaths({required this.profilesDir, Filesystem? fs})
    : fs = fs ?? AppStorage.fs;

  final String profilesDir;
  final Filesystem fs;
}

class ProjectProfileRepository {
  ProjectProfileRepository({String? rootDir, StorageRoots? storageRoots})
    : _rootOverride = rootDir,
      _storageRoots = storageRoots;

  final String? _rootOverride;
  final StorageRoots? _storageRoots;

  Future<_ProjectProfilePaths> _paths() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      final pathCtx = AppPaths.pathContextForDataRoot(snap.appProjectsDir);
      return _ProjectProfilePaths(
        profilesDir: pathCtx.join(snap.appProjectsDir, 'profiles'),
        fs: snap.fs,
      );
    }
    final root = _rootOverride ?? AppStorage.paths.appProjectsDir;
    final pathCtx = AppPaths.pathContextForDataRoot(root);
    return _ProjectProfilePaths(
      profilesDir: pathCtx.join(root, 'profiles'),
    );
  }

  String _profileFile(_ProjectProfilePaths paths, String projectId) {
    return paths.fs.pathContext.join(paths.profilesDir, '$projectId.json');
  }

  Future<ProjectProfile?> load(String projectId) async {
    final paths = await _paths();
    final filePath = _profileFile(paths, projectId);
    final stat = await paths.fs.stat(filePath);
    if (!stat.exists) return null;

    final raw = await paths.fs.readString(filePath);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ProjectProfile.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return null;
    }
  }

  Future<void> save(ProjectProfile profile) async {
    final paths = await _paths();
    final filePath = _profileFile(paths, profile.projectId);
    await paths.fs.ensureDir(paths.profilesDir);
    await paths.fs.atomicWrite(
      filePath,
      const JsonEncoder.withIndent('  ').convert(profile.toJson()),
    );
  }

  Future<ProjectProfile> createDefault(String projectId) async {
    return ProjectProfile(
      projectId: projectId,
    );
  }

  Future<ProjectProfile> loadOrCreate(String projectId) async {
    final existing = await load(projectId);
    if (existing != null) return existing;

    final profile = await createDefault(projectId);
    await save(profile);
    return profile;
  }
}
