import 'dart:async';
import 'dart:convert';

import '../models/personal_profile.dart';
import '../models/team_config.dart';
import '../models/launch_profile.dart';
import '../services/io/filesystem.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/storage/app_storage.dart';
import '../utils/logger.dart';
import 'launch_profile_index_store.dart';

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
  static final Map<String, List<LaunchProfile>> _loadAllByRoot = {};
  Future<void>? _revalidationFuture;

  Future<void> _awaitIndexQuiescence() async {
    final pending = _revalidationFuture;
    if (pending != null) await pending;
  }

  void _scheduleRevalidation(
    ({String dir, Filesystem fs}) paths,
    LaunchProfileIndexStore store,
    List<LaunchProfile> snapshot,
  ) {
    Future<void>? pending;
    pending = _revalidateLaunchProfilesSnapshot(
      paths,
      store,
      snapshot,
    ).whenComplete(() {
      if (identical(_revalidationFuture, pending)) {
        _revalidationFuture = null;
      }
    });
    _revalidationFuture = pending;
    unawaited(pending);
  }

  String _loadAllCacheKey() {
    if (_rootDirOverride != null) return _rootDirOverride;
    if (AppStorage.isInstalled) return AppStorage.appDataRoot;
    return AppPathsBootstrapper.current.basePath;
  }

  void _invalidateLoadAllCache() {
    _loadAllByRoot.remove(_loadAllCacheKey());
  }

  List<LaunchProfile> _rememberLoadAll(List<LaunchProfile> profiles) {
    final remembered = List<LaunchProfile>.unmodifiable(profiles);
    _loadAllByRoot[_loadAllCacheKey()] = remembered;
    return remembered;
  }

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

  LaunchProfileIndexStore _indexStore(({String dir, Filesystem fs}) paths) =>
      LaunchProfileIndexStore(launchProfilesDir: paths.dir, fs: paths.fs);

  Future<List<String>> _listProfileIds(({String dir, Filesystem fs}) paths) async {
    try {
      final entries = await paths.fs.listDir(paths.dir);
      final ids = await Future.wait(
        entries.where((e) => e.isDirectory).map((entry) async {
          final file = _profileFile(paths.fs, paths.dir, entry.name);
          if ((await paths.fs.stat(file)).exists) return entry.name;
          return null;
        }),
      );
      return [for (final id in ids) if (id != null) id];
    } on Object {
      return const [];
    }
  }

  static bool _sameProfileIds(List<String> diskIds, List<LaunchProfile> snapshot) {
    if (diskIds.length != snapshot.length) return false;
    final diskSet = diskIds.toSet();
    return snapshot.every((profile) => diskSet.contains(profile.id));
  }

  Future<List<LaunchProfile>> loadAll() async {
    final cached = _loadAllByRoot[_loadAllCacheKey()];
    if (cached != null) {
      appLogger.i(
        '[boot] loadLaunchProfiles from memory count=${cached.length}',
      );
      return cached;
    }
    final paths = await _paths();
    final store = _indexStore(paths);
    final readSw = Stopwatch()..start();
    final snapshot = await store.tryRead();
    final readMs = readSw.elapsedMilliseconds;
    if (snapshot != null) {
      appLogger.i(
        '[boot] loadLaunchProfiles from snapshot count=${snapshot.length} '
        'read=${readMs}ms (validate deferred)',
      );
      _scheduleRevalidation(paths, store, snapshot);
      return _rememberLoadAll(_sorted(snapshot));
    } else {
      appLogger.i(
        '[boot] loadLaunchProfiles rebuilding snapshot read=${readMs}ms',
      );
    }
    final profiles = await _scanAll(paths);
    await store.writeAll(profiles);
    return _rememberLoadAll(profiles);
  }

  Future<void> _revalidateLaunchProfilesSnapshot(
    ({String dir, Filesystem fs}) paths,
    LaunchProfileIndexStore store,
    List<LaunchProfile> snapshot,
  ) async {
    final validateSw = Stopwatch()..start();
    final diskIds = await _listProfileIds(paths);
    final validateMs = validateSw.elapsedMilliseconds;
    if (_sameProfileIds(diskIds, snapshot)) {
      appLogger.i(
        '[boot] loadLaunchProfiles validate ok +${validateMs}ms',
      );
      return;
    }
    appLogger.i(
      '[boot] loadLaunchProfiles snapshot stale '
      'disk=${diskIds.length} index=${snapshot.length} '
      'validate=${validateMs}ms',
    );
    final profiles = await _scanAll(paths);
    await store.writeAll(profiles);
    _rememberLoadAll(profiles);
  }

  Future<List<LaunchProfile>> _scanAll(({String dir, Filesystem fs}) paths) async {
    try {
      final entries = await paths.fs.listDir(paths.dir);
      final profiles = await Future.wait(
        entries.where((e) => e.isDirectory).map((entry) async {
          final file = _profileFile(paths.fs, paths.dir, entry.name);
          final content = await paths.fs.readString(file);
          if (content == null || content.isEmpty) return null;
          try {
            final decoded = jsonDecode(content);
            if (decoded is! Map) return null;
            return _decode(Map<String, Object?>.from(decoded));
          } on FormatException {
            return null;
          }
        }),
      );
      final out = [
        for (final profile in profiles)
          if (profile != null) profile,
      ];
      return _sorted(out);
    } on Object {
      return const [];
    }
  }

  static List<LaunchProfile> _sorted(List<LaunchProfile> out) {
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

  LaunchProfile _decode(Map<String, Object?> json) =>
      LaunchProfileIndexStore.decodeProfile(json);

  Future<void> save(LaunchProfile identity) async {
    final id = identity.id.trim();
    if (id.isEmpty) return;
    await _awaitIndexQuiescence();
    final paths = await _paths();
    final dir = paths.fs.pathContext.join(paths.dir, id);
    await paths.fs.ensureDir(dir);
    await paths.fs.atomicWrite(
      _profileFile(paths.fs, paths.dir, id),
      const JsonEncoder.withIndent('  ').convert(identity.toJson()),
    );
    _invalidateLoadAllCache();
    await _indexStore(paths).upsert(identity);
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
    await _awaitIndexQuiescence();
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
    _invalidateLoadAllCache();
    await _indexStore(paths).remove(trimmed);
  }
}
