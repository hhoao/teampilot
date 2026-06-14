import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_provider/brand_dropdown_rows.dart';
import '../../widgets/app_provider/cli_effort_picker_field.dart';
import '../../widgets/app_provider/provider_brand_icon.dart';
import '../../widgets/app_provider/provider_model_picker_field.dart';
import '../../widgets/cli/cli_brand_icon.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../home_workspace/project/config/project_cli_config_helpers.dart';
import 'team_config_helpers.dart';
import 'team_member_launch_config_helpers.dart';

const _inheritCliToken = '__inherit__';

/// Summary row + configure dialog for member CLI / provider / model / effort.
class MemberLaunchConfigRow extends StatelessWidget {
  const MemberLaunchConfigRow({
    required this.team,
    required this.member,
    required this.cubit,
    this.showDividerBelow = true,
    super.key,
  });

  final TeamConfig team;
  final TeamMemberConfig member;
  final TeamCubit cubit;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final registry = CliToolRegistryScope.of(context);
    final catalogCli = memberCatalogCliFor(team, member);
    final catalogDef = registry.tryGet(catalogCli);
    final providers = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(catalogCli)
        .toList(growable: false);
    AppProviderConfig? selectedProvider;
    final prov = member.provider.trim();
    if (prov.isNotEmpty) {
      for (final p in providers) {
        if (p.id == prov) {
          selectedProvider = p;
          break;
        }
      }
    }
    final hidesModelPicker = projectCliHidesModelPicker(
      registry,
      catalogCli,
      selectedProvider,
    );
    final configured = memberLaunchIsConfigured(
      member: member,
      registry: registry,
      catalogCli: catalogCli,
      provider: selectedProvider,
    );
    final configLine = memberLaunchConfigLine(
      l10n: l10n,
      registry: registry,
      team: team,
      member: member,
      configured: configured,
      provider: selectedProvider,
      hidesModelPicker: hidesModelPicker,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              configured &&
                      selectedProvider != null &&
                      selectedProvider.icon.isNotEmpty
                  ? ProviderBrandIcon.fromConfig(
                      selectedProvider,
                      size: 40,
                      borderRadius: 10,
                    )
                  : catalogDef != null
                  ? CliBrandIcon(
                      cli: catalogCli,
                      definition: catalogDef,
                      label: cliDisplayName(catalogDef, l10n),
                      size: 40,
                      borderRadius: 10,
                    )
                  : _LaunchIcon(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            l10n.memberLaunchConfigTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: styles.prominent.copyWith(
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SettingsConfiguredBadge(configured: configured),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (!configured)
                      Text(
                        l10n.memberLaunchConfigSubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: styles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    const SizedBox(height: 2),
                    if (configured)
                      Text(
                        configLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: styles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _openMemberLaunchConfigureDialog(
                  context,
                  team: team,
                  member: member,
                  cubit: cubit,
                ),
                icon: Icon(Icons.tune, size: context.appIconSizes.sm),
                label: Text(l10n.projectCliConfigure),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDividerBelow)
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
      ],
    );
  }
}

class _LaunchIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Icon(Icons.rocket_launch_outlined, size: 22, color: cs.primary),
    );
  }
}

Future<void> _openMemberLaunchConfigureDialog(
  BuildContext context, {
  required TeamConfig team,
  required TeamMemberConfig member,
  required TeamCubit cubit,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) =>
        MemberLaunchConfigureDialog(team: team, member: member, cubit: cubit),
  );
}

class MemberLaunchConfigureDialog extends StatefulWidget {
  const MemberLaunchConfigureDialog({
    required this.team,
    required this.member,
    required this.cubit,
    super.key,
  });

  final TeamConfig team;
  final TeamMemberConfig member;
  final TeamCubit cubit;

  @override
  State<MemberLaunchConfigureDialog> createState() =>
      _MemberLaunchConfigureDialogState();
}

class _MemberLaunchConfigureDialogState
    extends State<MemberLaunchConfigureDialog> {
  late String _cliToken;
  late String _providerId;
  late String _modelId;
  late String _effortId;

  @override
  void initState() {
    super.initState();
    _cliToken = widget.member.cli?.value ?? _inheritCliToken;
    _providerId = widget.member.provider;
    _modelId = widget.member.model;
    _effortId = widget.member.effort;
  }

  CliTool get _catalogCli {
    if (widget.team.teamMode != TeamMode.mixed) {
      return widget.team.cli;
    }
    if (_cliToken == _inheritCliToken) {
      return widget.team.cli;
    }
    return CliTool.decode(_cliToken);
  }

  AppProviderConfig? _selectedProvider(Iterable<AppProviderConfig> providers) {
    for (final provider in providers) {
      if (provider.id == _providerId) return provider;
    }
    return null;
  }

  void _applyCatalogCliChange(String token) {
    setState(() {
      _cliToken = token;
      _providerId = '';
      _modelId = '';
      _effortId = '';
    });
  }

  void _save() {
    final mixed = widget.team.teamMode == TeamMode.mixed;
    final nextCli = mixed && _cliToken != _inheritCliToken
        ? CliTool.decode(_cliToken)
        : null;
    widget.cubit.updateMember(
      widget.member.id,
      widget.member.copyWith(
        cli: nextCli,
        updateCli: mixed,
        provider: _providerId,
        model: _modelId,
        effort: _effortId,
        updateEffort: true,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final dropdownDeco = AppDropdownDecorations.themed(context);
    final catalogCli = _catalogCli;
    final providers = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(catalogCli)
        .toList(growable: false);
    final providerIds = providers.map((p) => p.id).toList()..sort();
    if (_providerId.trim().isNotEmpty && !providerIds.contains(_providerId)) {
      providerIds.add(_providerId);
    }
    final providerLabels = {
      for (final provider in providers) provider.id: provider.name,
      if (_providerId.trim().isNotEmpty &&
          !providers.any((p) => p.id == _providerId))
        _providerId: _providerId,
    };
    final selectedProvider = _selectedProvider(providers);
    final hideModelPicker = projectCliHidesModelPicker(
      registry,
      catalogCli,
      selectedProvider,
    );
    final showEffortPicker = teamShowsEffortPicker(
      context,
      cli: catalogCli,
      placement: EffortPickerPlacement.member,
      model: _modelId,
    );
    final mixed = widget.team.teamMode == TeamMode.mixed;
    final cliItems = mixed
        ? [_inheritCliToken, ...registry.launchable.map((d) => d.id.value)]
        : const <String>[];

    return AppDialog(
      maxWidth: 680,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.memberLaunchConfigTitle),
          const SizedBox(height: 16),
          SettingsSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (mixed)
                  SettingsLabeledRow(
                    title: l10n.teamCliLabel,
                    trailing: _memberLaunchDropdown(
                      AppDropdownField<String>(
                        items: cliItems,
                        initialItem: _cliToken,
                        decoration: dropdownDeco,
                        itemLabel: (value) {
                          if (value == _inheritCliToken) {
                            return l10n.memberCliInheritHint;
                          }
                          final def = registry.tryGet(CliTool.decode(value));
                          return def == null
                              ? value
                              : cliDisplayName(def, l10n);
                        },
                        onChanged: (value) {
                          if (value == null) return;
                          if (value == _cliToken) return;
                          _applyCatalogCliChange(value);
                        },
                        itemBuilder: (context, value) {
                          if (value == _inheritCliToken) {
                            return Text(l10n.memberCliInheritHint);
                          }
                          final cli = CliTool.decode(value);
                          final def = registry.tryGet(cli);
                          return cliDropdownRow(
                            context,
                            cli: cli,
                            label: def == null
                                ? value
                                : cliDisplayName(def, l10n),
                            registry: registry,
                          );
                        },
                      ),
                    ),
                    showDividerBelow: true,
                  ),
                SettingsLabeledRow(
                  title: l10n.provider,
                  trailing: _memberLaunchDropdown(
                    AppDropdownField<String>(
                      key: ValueKey(
                        'member-launch-provider-$catalogCli-$_providerId',
                      ),
                      items: providerIds,
                      initialItem: _providerId.isEmpty ? null : _providerId,
                      hintText: l10n.selectProvider,
                      decoration: dropdownDeco,
                      onChanged: (value) {
                        setState(() {
                          _providerId = value ?? '';
                          _modelId = '';
                          _effortId = '';
                        });
                      },
                      itemBuilder: providerDropdownItemBuilder(
                        providers: providers,
                        labelFor: (value) => providerLabels[value] ?? value,
                      ),
                    ),
                  ),
                  showDividerBelow: !hideModelPicker || showEffortPicker,
                ),
                if (!hideModelPicker)
                  SettingsLabeledRow(
                    title: l10n.model,
                    trailing: _memberLaunchDropdown(
                      ProviderModelPickerField(
                        key: ValueKey(
                          'member-launch-model-$_providerId-$_modelId',
                        ),
                        cli: catalogCli,
                        providerId: _providerId,
                        provider: selectedProvider,
                        value: _modelId,
                        hintText: l10n.selectModel,
                        decoration: dropdownDeco,
                        onChanged: (value) => setState(() {
                          _modelId = value.trim();
                          if (!teamShowsEffortPicker(
                            context,
                            cli: catalogCli,
                            placement: EffortPickerPlacement.member,
                            model: _modelId,
                          )) {
                            _effortId = '';
                          }
                        }),
                      ),
                    ),
                    showDividerBelow: showEffortPicker,
                  ),
                if (showEffortPicker)
                  SettingsLabeledRow(
                    title: l10n.memberEffortLevel,
                    subtitle: l10n.memberEffortLevelSubtitle,
                    trailing: _memberLaunchDropdown(
                      CliEffortPickerField(
                        key: ValueKey(
                          'member-launch-effort-$_providerId-$_modelId-$_effortId',
                        ),
                        cli: catalogCli,
                        value: _effortId,
                        team: widget.team,
                        member: widget.member,
                        provider: selectedProvider,
                        model: _modelId,
                        allowInherit: true,
                        inheritLabel: l10n.memberEffortInheritHint,
                        decoration: dropdownDeco,
                        onChanged: (value) =>
                            setState(() => _effortId = value.trim()),
                      ),
                    ),
                    showDividerBelow: false,
                  ),
              ],
            ),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: _providerId.trim().isEmpty ? null : _save,
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _memberLaunchDropdownMinWidth = 180.0;

Widget _memberLaunchDropdown(Widget child) {
  return ConstrainedBox(
    constraints: const BoxConstraints(minWidth: _memberLaunchDropdownMinWidth),
    child: child,
  );
}
