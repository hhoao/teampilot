import 'dart:convert';

import '../models/project_profile.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/storage_resolver.dart';
import '../services/storage/workspace_layout.dart';

class ProjectProfileRepository {
  ProjectProfileRepository({String? rootDir, StorageRoots? storageRoots})
    : _rootOverride = rootDir,
      _storageRoots = storageRoots;

  final String? _rootOverride;
  final StorageRoots? _storageRoots;

  Future<({WorkspaceLayout layout, Filesystem fs})> _paths() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      return (layout: snap.workspace, fs: snap.fs);
    }
    final root = _rootOverride ?? AppStorage.paths.basePath;
    final fs = AppStorage.fs;
    return (
      layout: WorkspaceLayout(teampilotRoot: root, fs: fs),
      fs: fs,
    );
  }

  String _profileFile(WorkspaceLayout layout, String projectId) {
    return layout.profileFile(projectId);
  }

  Future<ProjectProfile?> load(String projectId) async {
    final paths = await _paths();
    final filePath = _profileFile(paths.layout, projectId);
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
    final filePath = _profileFile(paths.layout, profile.projectId);
    await paths.fs.ensureDir(paths.layout.projectDir(profile.projectId));
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
