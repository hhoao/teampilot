import 'dart:io';

import '../models/skill.dart';
import '../services/skill/skill_fetch_service.dart';
import '../services/skill/skill_install_service.dart';
import '../services/skill/skill_manifest_service.dart';
import '../services/skill/skill_repo_disk_cache_service.dart';

class SkillRepository {
  factory SkillRepository({
    SkillManifestService? manifest,
    SkillFetchService? fetch,
    SkillRepoDiskCacheService? repoCache,
    SkillInstallService? install,
  }) {
    final resolvedFetch = fetch ?? SkillFetchService();
    final resolvedManifest = manifest ?? SkillManifestService();
    final resolvedCache =
        repoCache ?? SkillRepoDiskCacheService(fetch: resolvedFetch);
    return SkillRepository._(
      manifest: resolvedManifest,
      fetch: resolvedFetch,
      repoCache: resolvedCache,
      install:
          install ??
          SkillInstallService(
            manifest: resolvedManifest,
            fetch: resolvedFetch,
            repoCache: resolvedCache,
          ),
    );
  }

  SkillRepository._({
    required this.manifest,
    required this.fetch,
    required this.repoCache,
    required this.install,
  });

  final SkillManifestService manifest;
  final SkillFetchService fetch;
  final SkillRepoDiskCacheService repoCache;
  final SkillInstallService install;

  Future<List<Skill>> loadInstalled() => manifest.loadSkills();

  Future<List<DiscoverableSkill>> readCachedDiscoverable(SkillRepo repo) =>
      repoCache.readSkillsFromDisk(repo);

  Future<SkillRepoSyncResult> syncRepoCache(
    SkillRepo repo, {
    bool force = false,
    Duration? maxStaleness,
  }) => repoCache.ensureSynced(repo, force: force, maxStaleness: maxStaleness);

  /// True when the repo was synced to disk at least once (meta.json exists).
  Future<bool> hasCachedSnapshot(SkillRepo repo) async =>
      (await repoCache.readMeta(repo)) != null;

  Future<void> deleteRepoCache(SkillRepo repo) =>
      repoCache.deleteRepoCache(repo);

  Future<List<SkillUpdateInfo>> checkUpdates(List<Skill> installed) =>
      install.checkUpdates(installed);

  Future<Skill> installFromDiscovery(
    DiscoverableSkill d, {
    bool overwrite = false,
    String? idOverride,
  }) => install.installFromDiscovery(
    d,
    overwrite: overwrite,
    idOverride: idOverride,
  );

  Future<List<Skill>> installFromZip(File zip, {bool overwrite = false}) =>
      install.installFromZip(zip, overwrite: overwrite);

  Future<void> uninstall(Skill s) async {
    await install.uninstall(s);
  }

  Future<Skill> updateSkill(Skill s) => install.updateSkill(s);

  Future<List<UnmanagedSkill>> scanUnmanaged() => install.scanUnmanaged();
  Future<List<Skill>> importUnmanaged(List<UnmanagedSkill> us) =>
      install.importUnmanaged(us);

  Future<void> toggleSkillEnabled(Skill s, bool enabled) =>
      manifest.upsertSkill(
        s.copyWith(
          enabled: enabled,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
}
