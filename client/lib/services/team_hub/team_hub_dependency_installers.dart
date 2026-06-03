import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/discoverable_team.dart';
import '../../models/mcp_server.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../repositories/mcp_repository.dart';
import '../../utils/logger.dart';
import '../plugin/plugin_install_service.dart';
import '../plugin/plugin_repo_disk_cache_service.dart';
import '../skill/skill_install_service.dart';
import '../team/team_clone_service.dart';

/// Builds a [SkillDepInstaller] over [SkillInstallService]. If the skill is
/// already installed, the deterministic id (`owner/name:basename`) is returned
/// without re-downloading.
SkillDepInstaller skillInstallerFor(SkillInstallService service) {
  return (SkillDependencyRef ref) async {
    final expectedId = ref.expectedLocalId;
    try {
      final skill = await service.installFromDiscovery(
        DiscoverableSkill(
          key: expectedId,
          name: ref.name,
          description: '',
          directory: ref.directory,
          repoOwner: ref.repoOwner,
          repoName: ref.repoName,
          repoBranch: ref.repoBranch,
        ),
      );
      return skill.id;
    } on SkillInstallException catch (e) {
      // "already exists" => treat as installed; reuse the deterministic id.
      if (e.message.toLowerCase().contains('already exists')) {
        return expectedId;
      }
      appLogger.w('[team-hub] skill dep ${ref.name} failed: ${e.message}');
      return null;
    } catch (e) {
      appLogger.w('[team-hub] skill dep ${ref.name} failed: $e');
      return null;
    }
  };
}

/// Builds a [PluginDepInstaller] over the marketplace sync + install path.
PluginDepInstaller pluginInstallerFor(
  PluginInstallService install,
  PluginRepoDiskCacheService diskCache,
) {
  return (PluginDependencyRef ref) async {
    try {
      final marketplace = PluginMarketplace(
        owner: ref.marketplaceOwner,
        name: ref.marketplaceName,
        branch: ref.marketplaceBranch,
      );
      final dirPath = await diskCache.syncMarketplace(marketplace);
      final discoverable = diskCache.parseMarketplaceManifest(
        directory: dirPath,
        marketplace: marketplace,
      );
      DiscoverablePlugin? match;
      for (final d in discoverable) {
        if (d.name == ref.entryName) {
          match = d;
          break;
        }
      }
      if (match == null) {
        appLogger.w('[team-hub] plugin ${ref.entryName} not in marketplace');
        return null;
      }
      final sourceDir = Directory(p.join(dirPath, match.source));
      if (!sourceDir.existsSync()) return null;
      final plugin = await install.installFromDirectory(
        sourceDir,
        marketplace: marketplace,
        marketplaceEntryName: ref.entryName,
      );
      return plugin.id;
    } catch (e) {
      appLogger.w('[team-hub] plugin dep ${ref.name} failed: $e');
      return null;
    }
  };
}

/// Builds an [McpDepInstaller] over [McpRepository]. Skips if id already present.
McpDepInstaller mcpInstallerFor(McpRepository repo) {
  return (McpDependencyRef ref) async {
    try {
      final existing = await repo.findById(ref.id);
      if (existing != null) return existing.id;
      final now = DateTime.now().millisecondsSinceEpoch;
      final saved = await repo.upsert(McpServer(
        id: ref.id,
        name: ref.name,
        description: ref.description,
        server: ref.server,
        createdAt: now,
        updatedAt: now,
      ));
      return saved.id;
    } catch (e) {
      appLogger.w('[team-hub] mcp dep ${ref.name} failed: $e');
      return null;
    }
  };
}
