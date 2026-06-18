import 'dart:convert';

import '../models/identity_kind.dart';
import '../models/personal_identity.dart';
import '../models/team_config.dart';
import '../models/workspace_identity.dart';
import '../services/io/filesystem.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/storage_resolver.dart';

/// Persists [Identity] records (both kinds) at
/// `identities/{id}/identity.json`.
class IdentityRepository {
  IdentityRepository({
    String? rootDir,
    StorageRoots? storageRoots,
    SessionLifecycleService? lifecycleService,
  })  : _rootDirOverride = rootDir,
        _storageRoots = storageRoots,
        _lifecycleService = lifecycleService;

  final String? _rootDirOverride;
  final StorageRoots? _storageRoots;
  final SessionLifecycleService? _lifecycleService;

  Future<({String dir, Filesystem fs})> _paths() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      return (dir: snap.identitiesUiDir, fs: snap.fs);
    }
    return (
      dir: _rootDirOverride ?? AppPathsBootstrapper.current.identitiesDir,
      fs: AppStorage.fs,
    );
  }

  String _identityFile(Filesystem fs, String dir, String id) =>
      fs.pathContext.join(dir, id.trim(), 'identity.json');

  Future<List<Identity>> loadAll() async {
    final paths = await _paths();
    final out = <Identity>[];
    try {
      final entries = await paths.fs.listDir(paths.dir);
      for (final entry in entries) {
        if (!entry.isDirectory) continue;
        final file = _identityFile(paths.fs, paths.dir, entry.name);
        final content = await paths.fs.readString(file);
        if (content == null || content.isEmpty) continue;
        try {
          final decoded = jsonDecode(content);
          if (decoded is! Map) continue;
          out.add(_decode(Map<String, Object?>.from(decoded)));
        } on FormatException {
          continue;
        }
      }
    } on Object {
      return const [];
    }
    final sorted = List<Identity>.of(out)..sort(_compareIdentities);
    return List.unmodifiable(sorted);
  }

  static int _compareTeams(
    TeamIdentity a,
    TeamIdentity b, {
    required bool hasCustomOrder,
  }) {
    if (hasCustomOrder) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) return order;
    }
    if (a.createdAt != b.createdAt) {
      return a.createdAt.compareTo(b.createdAt);
    }
    return a.name.compareTo(b.name);
  }

  static int _compareIdentities(Identity a, Identity b) {
    if (a is TeamIdentity && b is TeamIdentity) {
      return _compareTeams(a, b, hasCustomOrder: false);
    }
    if (a is PersonalIdentity && b is PersonalIdentity) {
      return a.display.toLowerCase().compareTo(b.display.toLowerCase());
    }
    if (a is TeamIdentity) return -1;
    if (b is TeamIdentity) return 1;
    return a.display.toLowerCase().compareTo(b.display.toLowerCase());
  }

  Identity _decode(Map<String, Object?> json) {
    return switch (IdentityKind.decode(json['kind'])) {
      IdentityKind.personal => PersonalIdentity.fromJson(json),
      IdentityKind.team => TeamIdentity.fromJson(json),
    };
  }

  Future<void> save(Identity identity) async {
    final id = identity.id.trim();
    if (id.isEmpty) return;
    final paths = await _paths();
    final dir = paths.fs.pathContext.join(paths.dir, id);
    await paths.fs.ensureDir(dir);
    await paths.fs.atomicWrite(
      _identityFile(paths.fs, paths.dir, id),
      const JsonEncoder.withIndent('  ').convert(identity.toJson()),
    );
  }

  Future<List<TeamIdentity>> loadTeams() async {
    final teams = (await loadAll()).whereType<TeamIdentity>().toList();
    final hasCustomOrder = teams.any((team) => team.sortOrder > 0);
    teams.sort(
      (a, b) => _compareTeams(a, b, hasCustomOrder: hasCustomOrder),
    );
    return List.unmodifiable(teams);
  }

  Future<void> saveTeams(List<TeamIdentity> teams) async {
    for (final team in teams) {
      await save(team);
    }
  }

  Future<void> delete(String id, {bool destroyCliState = true}) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    if (destroyCliState) {
      await _lifecycleService?.destroyCliToolState(trimmed);
    }
    final paths = await _paths();
    try {
      await paths.fs.removeRecursive(
        paths.fs.pathContext.join(paths.dir, trimmed),
      );
    } on Object {
      // best effort
    }
  }
}
