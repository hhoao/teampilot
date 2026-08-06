import '../../models/discoverable_team.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../../services/expert_hub/local_expert_store.dart';
import 'bundle_provenance_lookup.dart';

/// Outcome of mapping a local [TeamProfile] for Hub publish.
sealed class TeamPublishMapResult {
  const TeamPublishMapResult();
}

final class PublishReadyTeam extends TeamPublishMapResult {
  const PublishReadyTeam(this.team);
  final DiscoverableTeam team;
}

final class PublishBlocked extends TeamPublishMapResult {
  const PublishBlocked(this.reasons);
  final List<String> reasons;
}

/// Maps a local [TeamProfile] to a portable [DiscoverableTeam] for registry JSON.
class TeamProfilePublishMapper {
  const TeamProfilePublishMapper._();

  static TeamPublishMapResult map({
    required TeamProfile team,
    required Map<String, String> expertKeyRemap,
    required BundleProvenanceLookup lookup,
    required String key,
    required String category,
    String? author,
    int? updatedAt,
  }) {
    final reasons = <String>[];

    final remappedRoster = <TeamRosterSlot>[];
    for (final slot in team.roster) {
      final remappedKey = expertKeyRemap[slot.expertKey] ?? slot.expertKey;
      if (LocalExpertStore.isLocalKey(remappedKey)) {
        reasons.add('Unresolved local expert key: ${slot.expertKey}');
        continue;
      }
      remappedRoster.add(
        slot.copyWith(
          expertKey: remappedKey,
          // Drop joinedAt — local-only; registry roster is expertKey + overrides.
          joinedAt: 0,
        ),
      );
    }

    final deps = lookup.resolve(
      skillIds: team.skillIds,
      pluginIds: team.pluginIds,
      mcpServerIds: team.mcpServerIds,
    );
    for (final id in deps.nonPortableIds) {
      reasons.add('Non-portable bundle dependency: $id');
    }

    if (reasons.isNotEmpty) {
      return PublishBlocked(reasons);
    }

    return PublishReadyTeam(
      DiscoverableTeam(
        key: key,
        name: team.name,
        description: team.description,
        category: category,
        author: author,
        updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        cli: team.cli,
        teamMode: team.teamMode,
        extraArgs: team.extraArgs,
        roster: remappedRoster,
        skillDeps: deps.skillDeps,
        pluginDeps: deps.pluginDeps,
        mcpDeps: deps.mcpDeps,
      ),
    );
  }
}
