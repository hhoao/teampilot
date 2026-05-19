import 'dart:io';

import '../models/skill.dart';
import '../services/skill_fetch_service.dart';
import '../services/skill_install_service.dart';
import '../services/skill_manifest_service.dart';
import '../services/skill_repo_disk_cache_service.dart';
import '../services/skill_repo_service.dart';
import '../services/skills_sh_service.dart';

class SkillRepository {
  factory SkillRepository({
    SkillManifestService? manifest,
    SkillFetchService? fetch,
    SkillRepoDiskCacheService? repoCache,
    SkillInstallService? install,
    SkillRepoService? repos,
    SkillsShService? skillsSh,
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
      repos: repos ?? SkillRepoService(),
      skillsSh: skillsSh ?? SkillsShService(),
    );
  }

  SkillRepository._({
    required this.manifest,
    required this.fetch,
    required this.repoCache,
    required this.install,
    required this.repos,
    required this.skillsSh,
  });

  final SkillManifestService manifest;
  final SkillFetchService fetch;
  final SkillRepoDiskCacheService repoCache;
  final SkillInstallService install;
  final SkillRepoService repos;
  final SkillsShService skillsSh;

  Future<List<Skill>> loadInstalled() => manifest.loadSkills();
  Future<List<SkillBackup>> loadBackups() => manifest.loadBackups();
  Future<List<SkillRepo>> loadRepos() => repos.loadRepos();

  Future<List<DiscoverableSkill>> readCachedDiscoverable(SkillRepo repo) =>
      repoCache.readSkillsFromDisk(repo);

  Future<SkillRepoSyncResult> syncRepoCache(
    SkillRepo repo, {
    bool force = false,
  }) => repoCache.ensureSynced(repo, force: force);

  Future<void> deleteRepoCache(SkillRepo repo) => repoCache.deleteRepoCache(repo);

  Future<List<SkillUpdateInfo>> checkUpdates(List<Skill> installed) =>
      install.checkUpdates(installed);

  Future<Skill> installFromDiscovery(
    DiscoverableSkill d, {
    bool overwrite = false,
  }) => install.installFromDiscovery(d, overwrite: overwrite);

  Future<List<Skill>> installFromZip(File zip, {bool overwrite = false}) =>
      install.installFromZip(zip, overwrite: overwrite);

  Future<SkillBackup> uninstall(Skill s) => install.uninstall(s);
  Future<Skill> restoreBackup(SkillBackup b) => install.restoreBackup(b);
  Future<void> deleteBackup(SkillBackup b) => install.deleteBackup(b);
  Future<Skill> updateSkill(Skill s) => install.updateSkill(s);

  Future<List<UnmanagedSkill>> scanUnmanaged() => install.scanUnmanaged();
  Future<List<Skill>> importUnmanaged(List<UnmanagedSkill> us) =>
      install.importUnmanaged(us);

  Future<SkillsShResult> searchSkillsSh(
    String q, {
    int limit = 20,
    int offset = 0,
  }) => skillsSh.search(q, limit: limit, offset: offset);

  Future<void> toggleSkillEnabled(Skill s, bool enabled) =>
      manifest.upsertSkill(
        s.copyWith(
          enabled: enabled,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
}
