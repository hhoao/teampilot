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
    final providers = context.watch<AppProviderCubit>().state.providers;

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
        for (final tool in AppProviderTool.values) ...[
          _ToolRow(
            label: _toolLabel(l10n, tool),
            tool: tool,
            providers: providers,
            selectedId: team.providerIdsByTool[tool.value] ?? '',
            onSelected: (id) {
              final next = Map<String, String>.from(team.providerIdsByTool);
              if (id == null || id.isEmpty) {
                next.remove(tool.value);
              } else {
                next[tool.value] = id;
              }
              onChanged(team.copyWith(providerIdsByTool: next));
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  String _toolLabel(dynamic l10n, AppProviderTool tool) {
    return switch (tool) {
      AppProviderTool.flashskyai => l10n.appProviderToolFlashskyai,
      AppProviderTool.codex => l10n.appProviderToolCodex,
      AppProviderTool.claude => l10n.appProviderToolClaude,
    };
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.label,
    required this.tool,
    required this.providers,
    required this.selectedId,
    required this.onSelected,
  });

  final String label;
  final AppProviderTool tool;
  final List<AppProviderConfig> providers;
  final String selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final eligible = providers
        .where((p) => p.enables(tool))
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
