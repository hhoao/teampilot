import 'package:flutter/foundation.dart';

import '../../models/discoverable_team.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../expert_hub/expert_clone_service.dart';

/// Installs one skill dep; returns its local skill id, or null on failure.
typedef SkillDepInstaller = Future<String?> Function(SkillDependencyRef ref);

/// Installs one plugin dep; returns its local plugin id, or null on failure.
typedef PluginDepInstaller = Future<String?> Function(PluginDependencyRef ref);

/// Adds one MCP dep; returns its local server id, or null on failure.
typedef McpDepInstaller = Future<String?> Function(McpDependencyRef ref);

/// Clones one roster expert for a team clone; returns the key the slot should
/// reference (kept or new local key), or null on failure.
typedef ExpertSlotCloner = Future<ExpertCloneOutcome?> Function({
  required String expertKey,
  String? originTeamKey,
});

/// Produces a per-clone-run [ExpertSlotCloner] (run-scoped memoization).
typedef ExpertSlotClonerFactory = ExpertSlotCloner Function();

/// Creates the cloned team; returns the new team id, or null on failure.
typedef ClonedTeamCreator =
    Future<String?> Function({
      required String name,
      required CliTool cli,
      required TeamMode teamMode,
      required List<TeamRosterSlot> roster,
      required List<String> skillIds,
      required List<String> pluginIds,
      required List<String> mcpServerIds,
      required String description,
      required String extraArgs,
      String? hubSourceKey,
    });

enum DependencyKind { skill, plugin, mcp, expert }

class DependencyFailure {
  const DependencyFailure(this.kind, this.name);
  final DependencyKind kind;
  final String name;
}

/// Per-kind ids successfully installed during a TeamHub clone.
class CloneDepInstallSummary {
  const CloneDepInstallSummary({
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpIds = const [],
    this.expertKeys = const [],
  });

  final List<String> skillIds;
  final List<String> pluginIds;
  final List<String> mcpIds;
  final List<String> expertKeys;

  int get skillCount => skillIds.length;
  int get pluginCount => pluginIds.length;
  int get mcpCount => mcpIds.length;
  int get expertCount => expertKeys.length;
  int get totalCount => skillCount + pluginCount + mcpCount + expertCount;
  bool get isEmpty => totalCount == 0;

  @override
  bool operator ==(Object other) =>
      other is CloneDepInstallSummary &&
      listEquals(skillIds, other.skillIds) &&
      listEquals(pluginIds, other.pluginIds) &&
      listEquals(mcpIds, other.mcpIds) &&
      listEquals(expertKeys, other.expertKeys);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(skillIds),
    Object.hashAll(pluginIds),
    Object.hashAll(mcpIds),
    Object.hashAll(expertKeys),
  );
}

class CloneResult {
  const CloneResult({
    required this.teamId,
    required this.installed,
    required this.failedDeps,
  });

  final String teamId;
  final CloneDepInstallSummary installed;
  final List<DependencyFailure> failedDeps;

  bool get hasFailures => failedDeps.isNotEmpty;
}

class CloneException implements Exception {
  CloneException(this.message);
  final String message;
  @override
  String toString() => 'CloneException: $message';
}

class CloneProgress {
  const CloneProgress(this.message, this.done, this.total);
  final String message;
  final int done;
  final int total;
}

/// Orchestrates cloning a public team: auto-pulls its dependencies (each failure
/// is non-blocking) and then creates the local team.
class TeamCloneService {
  TeamCloneService({
    required this.installSkill,
    required this.installPlugin,
    required this.installMcp,
    required this.expertClonerFactory,
    required this.createTeam,
  });

  final SkillDepInstaller installSkill;
  final PluginDepInstaller installPlugin;
  final McpDepInstaller installMcp;
  final ExpertSlotClonerFactory expertClonerFactory;
  final ClonedTeamCreator createTeam;

  Future<CloneResult> clone(
    DiscoverableTeam team, {
    void Function(CloneProgress)? onProgress,
  }) async {
    final failed = <DependencyFailure>[];
    final total =
        team.skillDeps.length +
        team.pluginDeps.length +
        team.mcpDeps.length +
        team.roster.where((s) => s.expertKey.trim().isNotEmpty).length;
    var done = 0;

    void progress(String msg) {
      done++;
      onProgress?.call(CloneProgress(msg, done, total));
    }

    final skillIds = <String>[];
    for (final dep in team.skillDeps) {
      final id = await installSkill(dep);
      if (id != null) {
        skillIds.add(id);
      } else {
        failed.add(DependencyFailure(DependencyKind.skill, dep.name));
      }
      progress(dep.name);
    }

    final pluginIds = <String>[];
    for (final dep in team.pluginDeps) {
      final id = await installPlugin(dep);
      if (id != null) {
        pluginIds.add(id);
      } else {
        failed.add(DependencyFailure(DependencyKind.plugin, dep.name));
      }
      progress(dep.name);
    }

    final mcpIds = <String>[];
    for (final dep in team.mcpDeps) {
      final id = await installMcp(dep);
      if (id != null) {
        mcpIds.add(id);
      } else {
        failed.add(DependencyFailure(DependencyKind.mcp, dep.name));
      }
      progress(dep.name);
    }

    final cloner = expertClonerFactory();
    final now = DateTime.now().millisecondsSinceEpoch;
    final clonedExpertKeys = <String>[];
    final repointedRoster = <TeamRosterSlot>[];
    for (final slot in team.roster) {
      final key = slot.expertKey.trim();
      final base = slot.joinedAt == 0 ? slot.copyWith(joinedAt: now) : slot;
      if (key.isEmpty) {
        repointedRoster.add(base);
        continue;
      }
      final outcome = await cloner(expertKey: key, originTeamKey: team.key);
      if (outcome == null) {
        failed.add(DependencyFailure(DependencyKind.expert, key));
        repointedRoster.add(base);
      } else {
        if (outcome.cloned) clonedExpertKeys.add(outcome.key);
        repointedRoster.add(
          outcome.key == key ? base : base.copyWith(expertKey: outcome.key),
        );
      }
      progress('expert:$key');
    }

    final teamId = await createTeam(
      name: team.name,
      cli: team.cli,
      teamMode: team.teamMode,
      roster: repointedRoster,
      skillIds: skillIds,
      pluginIds: pluginIds,
      mcpServerIds: mcpIds,
      description: team.description,
      extraArgs: team.extraArgs,
      hubSourceKey: team.key,
    );
    if (teamId == null) {
      throw CloneException('team creation failed for "${team.name}"');
    }
    return CloneResult(
      teamId: teamId,
      installed: CloneDepInstallSummary(
        skillIds: skillIds,
        pluginIds: pluginIds,
        mcpIds: mcpIds,
        expertKeys: clonedExpertKeys,
      ),
      failedDeps: failed,
    );
  }
}
