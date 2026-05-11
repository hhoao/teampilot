import 'dart:io';

import '../models/skill.dart';
import '../services/skill_fetch_service.dart';
import '../services/skill_install_service.dart';
import '../services/skill_manifest_service.dart';
import '../services/skill_repo_service.dart';
import '../services/skills_sh_service.dart';

class SkillRepository {
  SkillRepository({
    SkillManifestService? manifest,
    SkillFetchService? fetch,
    SkillInstallService? install,
    SkillRepoService? repos,
    SkillsShService? skillsSh,
  }) : manifest = manifest ?? SkillManifestService(),
       fetch = fetch ?? SkillFetchService(),
       repos = repos ?? const SkillRepoService(),
       skillsSh = skillsSh ?? SkillsShService(),
       install = install ??
           SkillInstallService(
             manifest: manifest ?? SkillManifestService(),
             fetch: fetch,
           );

  final SkillManifestService manifest;
  final SkillFetchService fetch;
  final SkillInstallService install;
  final SkillRepoService repos;
  final SkillsShService skillsSh;

  Future<List<Skill>> loadInstalled() => manifest.loadSkills();
  Future<List<SkillBackup>> loadBackups() => manifest.loadBackups();
  Future<List<SkillRepo>> loadRepos() => repos.loadRepos();

  Future<List<DiscoverableSkill>> discover(
    List<SkillRepo> enabledRepos,
  ) async {
    final futures = enabledRepos.where((r) => r.enabled).map((r) async {
      try {
        return await fetch.listSkills(r);
      } catch (_) {
        return const <DiscoverableSkill>[];
      }
    }).toList();
    final results = await Future.wait(futures);
    return results.expand((e) => e).toList();
  }

  Future<List<SkillUpdateInfo>> checkUpdates(List<Skill> installed) =>
      install.checkUpdates(installed);

  Future<Skill> installFromDiscovery(
    DiscoverableSkill d, {
    bool overwrite = false,
  }) =>
      install.installFromDiscovery(d, overwrite: overwrite);

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
  }) =>
      skillsSh.search(q, limit: limit, offset: offset);

  Future<void> toggleSkillEnabled(Skill s, bool enabled) => manifest.upsertSkill(
    s.copyWith(
      enabled: enabled,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );
}
