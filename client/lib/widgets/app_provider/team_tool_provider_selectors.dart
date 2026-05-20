import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../dropdown/flashsky_dropdown_field.dart';
import '../dropdown/flashskyai_dropdown_decoration.dart';

class TeamToolProviderSelectors extends StatelessWidget {
  const TeamToolProviderSelectors({
    required this.team,
    required this.onChanged,
    super.key,
  });

  final TeamConfig team;
  final ValueChanged<TeamConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final providerCli = _providerCliForTeamCli(team.cli);
    final providers = context.watch<AppProviderCubit>().state.providersFor(
      providerCli,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.appProviderTeamToolSection,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.appProviderTeamToolSubtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _CliProviderRow(
          label: l10n.appProviderCliLabel(providerCli),
          cli: providerCli,
          providers: providers,
          selectedId: team.providerIdsByTool[providerCli.value] ?? '',
          onSelected: (id) {
            final next = Map<String, String>.from(team.providerIdsByTool);
            if (id == null || id.isEmpty) {
              next.remove(providerCli.value);
            } else {
              next[providerCli.value] = id;
            }
            onChanged(team.copyWith(providerIdsByTool: next));
          },
        ),
      ],
    );
  }

  AppProviderCli _providerCliForTeamCli(TeamCli cli) {
    return switch (cli) {
      TeamCli.flashskyai => AppProviderCli.flashskyai,
      TeamCli.codex => AppProviderCli.codex,
      TeamCli.claude => AppProviderCli.claude,
    };
  }

}

class _CliProviderRow extends StatelessWidget {
  const _CliProviderRow({
    required this.label,
    required this.cli,
    required this.providers,
    required this.selectedId,
    required this.onSelected,
  });

  final String label;
  final AppProviderCli cli;
  final List<AppProviderConfig> providers;
  final String selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final eligible = providers
        .where((p) => p.cli == cli)
        .toList(growable: false);
    final items = <String>['', ...eligible.map((p) => p.id)];
    final effectiveSelectedId = items.contains(selectedId) ? selectedId : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        FlashskyDropdownField<String>(
          key: ValueKey('team-tool-$label-$effectiveSelectedId'),
          items: items,
          initialItem: effectiveSelectedId,
          hintText: l10n.appProviderTeamNone,
          decoration: FlashskyDropdownDecorations.denseField(context),
          itemLabel: (id) {
            if (id.isEmpty) return l10n.appProviderTeamNone;
            return eligible
                    .where((p) => p.id == id)
                    .map((p) => p.name)
                    .firstOrNull ??
                id;
          },
          onChanged: onSelected,
        ),
      ],
    );
  }
}
