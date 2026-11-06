import 'dart:convert';

import '../models/remote_target.dart';
import '../models/ssh_profile.dart';
import '../repositories/remote_target_repository.dart';
import '../services/io/filesystem.dart';
import '../services/storage/home_storage.dart';
import '../services/storage/storage_failure.dart';

class SshProfileRepository {
  /// When [targetRepo] is supplied this repository is a facade over the
  /// device-local remote-target catalog: profiles are projected from/to
  /// [RemoteTarget] records. Otherwise it keeps the legacy `profiles.json`
  /// behavior on the home control plane ([storage]) so existing callers and
  /// tests keep working unchanged.
  ///
  /// Defaults follow the home control plane ([storage], test convenience).
  /// Production must use [deviceLocalSshProfileRepository] so the catalog
  /// stays on-device when home is rebound to SSH.
  SshProfileRepository({
    RemoteTargetRepository? targetRepo,
    String? rootDir,
    Filesystem? fs,
    required HomeStorage storage,
  }) : _explicitTargetRepo = targetRepo,
       _rootDirOverride = rootDir,
       _fsOverride = fs,
       _storage = storage;

  final RemoteTargetRepository? _explicitTargetRepo;
  final String? _rootDirOverride;
  final Filesystem? _fsOverride;
  final HomeStorage _storage;

  /// Backing store for the lazily-derived [SshProfileRepositoryTargetRepo.targetRepo]
  /// when no explicit catalog was injected. Private so it does not widen the
  /// class interface (test fakes `implements SshProfileRepository`).
  RemoteTargetRepository? _derivedTargetRepo;

  String get _root => _rootDirOverride ?? _storage.paths.sshProfilesDir;

  Filesystem get _fs => _fsOverride ?? _storage.fs;

  String get _profilesFile => _fs.pathContext.join(_root, 'profiles.json');

  String get _selectedProfileFile =>
      _fs.pathContext.join(_root, 'selected_profile.txt');

  Future<List<SshProfile>> loadAll() async {
    final repo = _explicitTargetRepo;
    if (repo != null) {
      final targets = await repo.loadAll();
      return targets.map(SshProfile.fromTarget).toList();
    }
    return _loadAllLegacy();
  }

  Future<void> save(SshProfile profile) async {
    final repo = _explicitTargetRepo;
    if (repo != null) {
      await _saveFacade(repo, profile);
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
    if (_explicitTargetRepo != null) {
      for (final profile in profiles) {
        await save(profile);
      }
      return;
    }
    await _saveAllLegacy(profiles);
  }

  Future<void> delete(String profileId) async {
    final repo = _explicitTargetRepo;
    if (repo != null) {
      await repo.delete(profileId);
      return;
    }
    final profiles = await _loadAllLegacy();
    profiles.removeWhere((p) => p.id == profileId);
    await _saveAllLegacy(profiles);
  }

  Future<SshProfile?> findById(String profileId) async {
    final repo = _explicitTargetRepo;
    if (repo != null) {
      final target = await repo.findById(profileId);
      return target == null ? null : SshProfile.fromTarget(target);
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

  /// Facade projection of an [SshProfile] back into a [RemoteTarget]. A fresh
  /// target carries this save's timestamp and is flagged for sync.
  Future<void> _saveFacade(
    RemoteTargetRepository repo,
    SshProfile profile,
  ) async {
    final existing = await repo.findById(profile.id);
    final target =
        (existing ??
                RemoteTarget(
                  id: profile.id,
                  name: profile.name,
                  host: profile.host,
                  port: profile.port,
                  username: profile.username,
                ))
            .copyWith(
              name: profile.name,
              host: profile.host,
              port: profile.port,
              username: profile.username,
              authType: profile.authType,
              vaultEntryId: profile.vaultEntryId,
              endpoints: profile.endpoints,
              hostKeyFingerprints: profile.hostKeyFingerprints,
              lastGoodKind: profile.lastGoodKind,
              lastHome: profile.lastHome,
              lastAppDataRoot: profile.lastAppDataRoot,
              embeddedTarget: profile.embeddedTarget,
              relayUrl: profile.relayUrl,
              pairedDesktopId: profile.pairedDesktopId,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
              pendingSync: true,
            );
    await repo.save(target);
  }

  // ---- legacy `profiles.json` path, unchanged behavior ----

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

/// Public, non-null `targetRepo` accessor for sync consumers (a later task
/// reads `sshProfileRepo.targetRepo`). Declared as a same-library extension
/// rather than a class member so it adds nothing to the `SshProfileRepository`
/// instance interface: several test fakes `implements SshProfileRepository`
/// without `noSuchMethod`, and a new class getter would fail to compile there.
/// It returns the injected catalog when present, otherwise one derived lazily
/// from this repository's plane for callers that need it.
extension SshProfileRepositoryTargetRepo on SshProfileRepository {
  RemoteTargetRepository get targetRepo {
    final explicit = _explicitTargetRepo;
    if (explicit != null) return explicit;
    return _derivedTargetRepo ??= RemoteTargetRepository(
      rootDir: _root,
      fs: _fs,
    );
  }
}
