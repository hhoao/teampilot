import '../../models/mcp_server.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../../repositories/mcp_repository.dart';
import '../../repositories/plugin_repository.dart';
import '../../services/mcp/team_mcp_linker_service.dart';
import '../../services/plugin/team_plugin_linker_service.dart';
import '../../services/skill/team_skill_linker_service.dart';
import '../../utils/logger.dart';
import 'team_cubit_host.dart';
import 'team_profile_provisioner.dart';

typedef InstalledSkillsLoader = Future<List<Skill>> Function();
typedef InstalledPluginsLoader = Future<List<Plugin>> Function();
typedef InstalledMcpLoader = Future<List<McpServer>> Function();

/// Appends extension-contributed servers to [catalog]/[ids], de-duped by id.
(List<McpServer>, List<String>) mergeExtensionMcp({
  required List<McpServer> catalog,
  required List<String> ids,
  required List<McpServer> contributions,
}) {
  final existingIds = catalog.map((s) => s.id).toSet();
  final mergedCatalog = [...catalog];
  final mergedIds = [...ids];
  for (final server in contributions) {
    if (existingIds.add(server.id)) {
      mergedCatalog.add(server);
    }
    if (!mergedIds.contains(server.id)) {
      mergedIds.add(server.id);
    }
  }
  return (mergedCatalog, mergedIds);
}

/// Links a team's enabled skills/plugins/MCP servers into its config-profile
/// tree, pruning ids that no longer resolve to an installed item, and owns the
/// cross-team resource-removal flows.
class TeamResourceSyncService {
  TeamResourceSyncService({
    required TeamCubitHost host,
    required TeamProfileProvisioner provisioner,
    required TeamSkillLinkerService skillLinker,
    required TeamPluginLinkerService pluginLinker,
    required TeamMcpLinkerService mcpLinker,
    required PluginRepository pluginRepository,
    required McpRepository mcpRepository,
    InstalledSkillsLoader? installedSkillsLoader,
    InstalledPluginsLoader? installedPluginsLoader,
    InstalledMcpLoader? installedMcpLoader,
    required Future<List<McpServer>> Function(String teamId)
    extensionMcpContributor,
  }) : _h = host,
       _provisioner = provisioner,
       _skillLinker = skillLinker,
       _pluginLinker = pluginLinker,
       _mcpLinker = mcpLinker,
       _pluginRepository = pluginRepository,
       _mcpRepository = mcpRepository,
       _installedSkillsLoader = installedSkillsLoader,
       _installedPluginsLoader = installedPluginsLoader,
       _installedMcpLoader = installedMcpLoader,
       _extensionMcpContributor = extensionMcpContributor;

  final TeamCubitHost _h;
  final TeamProfileProvisioner _provisioner;
  final TeamSkillLinkerService _skillLinker;
  final TeamPluginLinkerService _pluginLinker;
  final TeamMcpLinkerService _mcpLinker;
  final PluginRepository _pluginRepository;
  final McpRepository _mcpRepository;
  final InstalledSkillsLoader? _installedSkillsLoader;
  final InstalledPluginsLoader? _installedPluginsLoader;
  final InstalledMcpLoader? _installedMcpLoader;
  final Future<List<McpServer>> Function(String teamId) _extensionMcpContributor;

  // ===== Cross-team removal =====

  Future<void> removeMcpFromAllTeams(String mcpId) async {
    final selected = _h.state.selectedTeam;
    final syncNeeded = selected != null && selected.mcpServerIds.contains(mcpId);
    var changed = false;
    final teams = [
      for (final team in _h.state.teams)
        if (team.mcpServerIds.contains(mcpId))
          () {
            changed = true;
            return team.copyWith(
              mcpServerIds: team.mcpServerIds
                  .where((id) => id != mcpId)
                  .toList(growable: false),
            );
          }()
        else
          team,
    ];
    if (!changed) return;
    _h.applyState(_h.state.copyWith(teams: teams));
    await _h.saveTeams(teams);
    if (syncNeeded) {
      await syncMcp();
    }
  }

  Future<void> removeSkillFromAllTeams(String skillId) async {
    final selected = _h.state.selectedTeam;
    final syncNeeded = selected != null && selected.skillIds.contains(skillId);
    var changed = false;
    final teams = [
      for (final team in _h.state.teams)
        if (team.skillIds.contains(skillId))
          () {
            changed = true;
            return team.copyWith(
              skillIds: team.skillIds
                  .where((id) => id != skillId)
                  .toList(growable: false),
            );
          }()
        else
          team,
    ];
    if (!changed) return;
    _h.applyState(_h.state.copyWith(teams: teams));
    await _h.saveTeams(teams);
    if (syncNeeded) {
      await syncSkills();
    }
  }

  Future<void> removePluginFromAllTeams(String pluginId) async {
    final affectedTeamIds = [
      for (final team in _h.state.teams)
        if (team.pluginIds.contains(pluginId)) team.id,
    ];
    if (affectedTeamIds.isEmpty) return;

    final teams = [
      for (final team in _h.state.teams)
        if (team.pluginIds.contains(pluginId))
          team.copyWith(
            pluginIds: team.pluginIds
                .where((id) => id != pluginId)
                .toList(growable: false),
          )
        else
          team,
    ];
    _h.applyState(_h.state.copyWith(teams: teams));
    await _h.saveTeams(teams);
    await syncPluginsForTeamIds(affectedTeamIds);
  }

  Future<void> syncTeamsUsingPlugin(
    String pluginId, {
    List<Plugin>? installed,
  }) async {
    final teamIds = [
      for (final team in _h.state.teams)
        if (team.pluginIds.contains(pluginId)) team.id,
    ];
    await syncPluginsForTeamIds(teamIds, installed: installed);
  }

  // ===== Skills =====

  Future<void> syncSkills({List<Skill>? installed}) async {
    final team = _h.state.selectedTeam;
    if (team == null) return;

    _h.applyState(_h.state.copyWith(isSyncingSkills: true));
    try {
      final List<Skill> catalog;
      if (installed != null) {
        catalog = installed;
      } else {
        catalog =
            await (_installedSkillsLoader?.call() ??
                Future.value(const <Skill>[]));
      }
      final enabled = catalog.where((s) => s.enabled).toList(growable: false);

      var result = await _skillLinker.syncForTeam(
        teamId: team.id,
        skillIds: team.skillIds,
        installed: enabled,
      );

      if (result.skippedMissingIds.isNotEmpty) {
        final prunedIds = team.skillIds
            .where((id) => !result.skippedMissingIds.contains(id))
            .toList(growable: false);
        if (prunedIds.length != team.skillIds.length) {
          final prunedTeam = team.copyWith(skillIds: prunedIds);
          final teams = [
            for (final t in _h.state.teams)
              if (t.id == team.id) prunedTeam else t,
          ];
          _h.applyState(_h.state.copyWith(teams: teams));
          await _h.saveTeams(teams);
          result = await _skillLinker.syncForTeam(
            teamId: team.id,
            skillIds: prunedIds,
            installed: enabled,
          );
        }
      }

      var status = _h.state.statusMessage;
      if (result.linked.isNotEmpty) {
        status = 'Linked ${result.linked.length} skill(s) for ${team.name}.';
      } else if (team.skillIds.isEmpty) {
        status = 'Cleared CLI skills for ${team.name}.';
      }
      if (result.skippedMissingIds.isNotEmpty) {
        status =
            '$status Removed ${result.skippedMissingIds.length} missing skill(s).';
      }
      if (result.errors.isNotEmpty) {
        status = result.errors.first;
        appLogger.w('[team-skills] sync errors: ${result.errors}');
      }
      _h.applyState(_h.state.copyWith(statusMessage: status));
    } catch (e) {
      appLogger.e('[team-skills] sync failed: $e');
      _h.applyState(_h.state.copyWith(statusMessage: 'Skill sync failed: $e'));
    } finally {
      _h.applyState(_h.state.copyWith(isSyncingSkills: false));
    }
  }

  // ===== MCP =====

  Future<void> syncMcp({List<McpServer>? installed}) async {
    final team = _h.state.selectedTeam;
    if (team == null) return;

    try {
      final List<McpServer> catalog;
      if (installed != null) {
        catalog = installed;
      } else {
        catalog =
            await (_installedMcpLoader?.call() ?? _mcpRepository.loadAll());
      }
      final enabled = catalog.where((s) => s.enabled).toList(growable: false);
      final contributions = await _extensionMcpContributor(team.id);
      final (mergedCatalog, mergedIds) = mergeExtensionMcp(
        catalog: enabled,
        ids: team.mcpServerIds,
        contributions: contributions,
      );
      final layout = (await _provisioner.service()).layout;

      var result = await _mcpLinker.syncForTeam(
        teamId: team.id,
        mcpServerIds: mergedIds,
        catalog: mergedCatalog,
        layout: layout,
      );

      if (result.skippedMissingIds.isNotEmpty) {
        final prunedIds = team.mcpServerIds
            .where((id) => !result.skippedMissingIds.contains(id))
            .toList(growable: false);
        if (prunedIds.length != team.mcpServerIds.length) {
          final prunedTeam = team.copyWith(mcpServerIds: prunedIds);
          final teams = [
            for (final t in _h.state.teams)
              if (t.id == team.id) prunedTeam else t,
          ];
          _h.applyState(_h.state.copyWith(teams: teams));
          await _h.saveTeams(teams);
          final (_, prunedMergedIds) = mergeExtensionMcp(
            catalog: enabled,
            ids: prunedIds,
            contributions: contributions,
          );
          result = await _mcpLinker.syncForTeam(
            teamId: team.id,
            mcpServerIds: prunedMergedIds,
            catalog: mergedCatalog,
            layout: layout,
          );
        }
      }

      if (result.errors.isNotEmpty) {
        appLogger.w('[team-mcp] sync errors: ${result.errors}');
        _h.applyState(_h.state.copyWith(statusMessage: result.errors.first));
      }
    } catch (e) {
      appLogger.e('[team-mcp] sync failed: $e');
      _h.applyState(_h.state.copyWith(statusMessage: 'MCP sync failed: $e'));
    }
  }

  // ===== Plugins =====

  Future<void> syncPluginsForSelected({List<Plugin>? installed}) async {
    final team = _h.state.selectedTeam;
    if (team == null) return;
    await syncPluginsForTeamIds([team.id], installed: installed);
  }

  Future<void> syncPluginsForTeamIds(
    Iterable<String> teamIds, {
    List<Plugin>? installed,
  }) async {
    final ids = teamIds.toList(growable: false);
    if (ids.isEmpty) return;

    _h.applyState(_h.state.copyWith(isSyncingPlugins: true));
    try {
      final catalog =
          installed ??
          await (_installedPluginsLoader?.call() ?? _pluginRepository.loadAll());

      var conflicts = _h.state.pluginSyncConflicts;
      for (final teamId in ids) {
        TeamConfig? team;
        for (final candidate in _h.state.teams) {
          if (candidate.id == teamId) {
            team = candidate;
            break;
          }
        }
        if (team == null) continue;

        final result = await _pluginLinker.syncForTeam(
          teamId: team.id,
          pluginIds: team.pluginIds,
          installed: catalog,
        );

        if (result.skippedMissingIds.isNotEmpty) {
          appLogger.w(
            '[team-plugins] skipped missing for ${team.id}: '
            '${result.skippedMissingIds}',
          );
        }

        if (result.errors.isNotEmpty) {
          appLogger.w(
            '[team-plugins] sync errors for ${team.id}: ${result.errors}',
          );
          if (team.id == _h.state.selectedTeamId) {
            _h.applyState(
              _h.state.copyWith(
                statusMessage:
                    'Plugin sync had ${result.errors.length} error(s): '
                    '${result.errors.first}',
              ),
            );
          }
        }

        if (team.id == _h.state.selectedTeamId) {
          conflicts = {
            for (final resolution in result.conflictResolutions)
              resolution.$1: resolution.$2,
          };
        }
      }

      _h.applyState(_h.state.copyWith(pluginSyncConflicts: conflicts));
    } catch (e) {
      appLogger.e('[team-plugins] sync failed: $e');
    } finally {
      _h.applyState(_h.state.copyWith(isSyncingPlugins: false));
    }
  }
}
