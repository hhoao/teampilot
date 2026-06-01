import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../dropdown/app_dropdown_field.dart';
import '../dropdown/app_dropdown_decoration.dart';
import '../settings/workspace_settings_widgets.dart';

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
    final providerCli =
        CliToolRegistryScope.maybeOf(
          context,
        )?.tryGet(team.cli.value)?.providerCatalogCli ??
        AppProviderCli.claude;
    final providers = context.watch<AppProviderCubit>().state.providersFor(
      providerCli,
    );
    final eligible = providers
        .where((p) => p.cli == providerCli)
        .toList(growable: false);
    final items = <String>['', ...eligible.map((p) => p.id)];
    final selectedId = team.providerIdsByTool[providerCli.value] ?? '';
    final effectiveSelectedId = items.contains(selectedId) ? selectedId : '';

    return SettingsLabeledStackedRow(
      title: l10n.appProviderTeamToolSection,
      subtitle: l10n.appProviderTeamToolSubtitle,
      body: AppDropdownField<String>(
        key: ValueKey('team-tool-provider-$effectiveSelectedId'),
        items: items,
        initialItem: effectiveSelectedId,
        hintText: l10n.appProviderTeamNone,
        decoration: AppDropdownDecorations.themed(context),
        itemLabel: (id) {
          if (id.isEmpty) return l10n.appProviderTeamNone;
          return eligible
                  .where((p) => p.id == id)
                  .map((p) => p.name)
                  .firstOrNull ??
              id;
        },
        onChanged: (id) {
          final next = Map<String, String>.from(team.providerIdsByTool);
          if (id == null || id.isEmpty) {
            next.remove(providerCli.value);
          } else {
            next[providerCli.value] = id;
          }
          onChanged(team.copyWith(providerIdsByTool: next));
        },
      ),
      showDividerBelow: false,
    );
  }
}
