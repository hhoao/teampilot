import 'dart:convert';

import '../models/launch_profile_kind.dart';
import '../models/personal_profile.dart';
import '../models/team_config.dart';
import '../models/launch_profile.dart';
import '../services/io/filesystem.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/storage/app_storage.dart';

/// Persists [LaunchProfile] records (both kinds) at
/// `launch-profiles/{id}/profile.json`.
class LaunchProfileRepository {
  LaunchProfileRepository({
    String? rootDir,
    SessionLifecycleService? lifecycleService,
  })  : _rootDirOverride = rootDir,
        _lifecycleService = lifecycleService;

  final String? _rootDirOverride;
  final SessionLifecycleService? _lifecycleService;

  Future<({String dir, Filesystem fs})> _paths() async {
    // Explicit rootDir override (tests) wins; otherwise the home control plane.
    if (_rootDirOverride != null) {
      return (dir: _rootDirOverride, fs: AppStorage.fs);
    }
    if (AppStorage.isInstalled) {
      final snap = AppStorage.context;
      return (dir: snap.launchProfilesDir, fs: snap.fs);
    }
    return (dir: AppPathsBootstrapper.current.launchProfilesDir, fs: AppStorage.fs);
  }

  String _profileFile(Filesystem fs, String dir, String id) =>
      fs.pathContext.join(dir, id.trim(), 'profile.json');

  Future<List<LaunchProfile>> loadAll() async {
    final paths = await _paths();
    final out = <LaunchProfile>[];
    try {
      final entries = await paths.fs.listDir(paths.dir);
      for (final entry in entries) {
        if (!entry.isDirectory) continue;
        final file = _profileFile(paths.fs, paths.dir, entry.name);
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
    final sorted = List<LaunchProfile>.of(out)..sort(_compareProfiles);
    return List.unmodifiable(sorted);
  }

  static int _compareTeams(
    TeamProfile a,
    TeamProfile b, {
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

  static int _comparePersonals(
    PersonalProfile a,
    PersonalProfile b, {
    required bool hasCustomOrder,
  }) {
    if (hasCustomOrder) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) return order;
    }
    if (a.createdAt != b.createdAt) {
      return a.createdAt.compareTo(b.createdAt);
    }
    return a.display.toLowerCase().compareTo(b.display.toLowerCase());
  }

  static int _compareProfiles(LaunchProfile a, LaunchProfile b) {
    if (a is TeamProfile && b is TeamProfile) {
      return _compareTeams(a, b, hasCustomOrder: false);
    }
    if (a is PersonalProfile && b is PersonalProfile) {
      return _comparePersonals(a, b, hasCustomOrder: false);
    }
    if (a is TeamProfile) return -1;
    if (b is TeamProfile) return 1;
    return a.display.toLowerCase().compareTo(b.display.toLowerCase());
  }

  LaunchProfile _decode(Map<String, Object?> json) {
    return switch (LaunchProfileKind.decode(json['kind'])) {
      LaunchProfileKind.personal => PersonalProfile.fromJson(json),
      LaunchProfileKind.team => TeamProfile.fromJson(json),
    };
  }

  Future<void> save(LaunchProfile identity) async {
    final id = identity.id.trim();
    if (id.isEmpty) return;
    final paths = await _paths();
    final dir = paths.fs.pathContext.join(paths.dir, id);
    await paths.fs.ensureDir(dir);
    await paths.fs.atomicWrite(
      _profileFile(paths.fs, paths.dir, id),
      const JsonEncoder.withIndent('  ').convert(identity.toJson()),
    );
  }

  Future<List<TeamProfile>> loadTeamProfiles() async {
    final teams = (await loadAll()).whereType<TeamProfile>().toList();
    final hasCustomOrder = teams.any((team) => team.sortOrder > 0);
    teams.sort(
      (a, b) => _compareTeams(a, b, hasCustomOrder: hasCustomOrder),
    );
    return List.unmodifiable(teams);
  }

  Future<List<PersonalProfile>> loadPersonalProfiles() async {
    final personals = (await loadAll()).whereType<PersonalProfile>().toList();
    final hasCustomOrder = personals.any((personal) => personal.sortOrder > 0);
    personals.sort(
      (a, b) => _comparePersonals(a, b, hasCustomOrder: hasCustomOrder),
    );
    return List.unmodifiable(personals);
  }

  Future<void> saveTeamProfiles(List<TeamProfile> teams) async {
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
