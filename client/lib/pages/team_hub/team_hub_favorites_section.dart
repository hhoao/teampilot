import 'package:flutter/material.dart';

import '../../cubits/team_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import 'team_hub_cards.dart';

class TeamHubFavoritesSection extends StatelessWidget {
  const TeamHubFavoritesSection({
    super.key,
    required this.cubit,
    required this.onOpen,
  });

  final TeamHubCubit cubit;
  final void Function(DiscoverableTeam) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final teams = cubit.favoriteTeams;
    if (teams.isEmpty) {
      return TeamHubEmptyBlock(
        icon: Icons.star_outline_rounded,
        title: l10n.teamHubFavoritesEmptyTitle,
        hint: l10n.teamHubFavoritesEmptyHint,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: 176,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: teams.length,
      itemBuilder: (context, i) {
        final t = teams[i];
        return TeamHubCard(
          team: t,
          favorited: true,
          busy: cubit.state.cloningKeys.contains(t.key),
          onTap: () => onOpen(t),
          onToggleFavorite: () => cubit.toggleFavorite(t.key),
        );
      },
    );
  }
}
