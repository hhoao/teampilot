import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/team/launch_profile_selectors.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/cli_preset.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_provider/provider_brand_icon.dart';
import '../../widgets/cli/cli_brand_icon.dart';
import '../../widgets/cli_launch_config/cli_launch_custom_fields.dart';
import '../../widgets/cli_launch_config/member_launch_config_kind.dart';
import '../../widgets/cli_launch_config/member_launch_config_type_field.dart';
import '../../widgets/cli_launch_config/preset_launch_picker_field.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../home_workspace/workspace/config/workspace_cli_config_helpers.dart';
import 'team_config_helpers.dart';
import 'team_member_launch_config_helpers.dart';

/// Summary row + configure dialog for member CLI / provider / model / effort.
class MemberLaunchConfigRow extends StatelessWidget {
  const MemberLaunchConfigRow({
    required this.teamId,
    required this.memberId,
    this.showDividerBelow = true,
    super.key,
  });

  final String teamId;
  final String memberId;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<LaunchProfileCubit, LaunchProfileState,
        MemberLaunchContext?>(
      selector: (state) =>
          LaunchProfileSelectors.memberLaunchContext(state, teamId, memberId),
      builder: (context, launchContext) {
        if (launchContext == null) return const SizedBox.shrink();
        return _MemberLaunchConfigRowBody(
          launchContext: launchContext,
          showDividerBelow: showDividerBelow,
        );
      },
    );
  }
}

class _MemberLaunchConfigRowBody extends StatelessWidget {
  const _MemberLaunchConfigRowBody({
    required this.launchContext,
    required this.showDividerBelow,
  });

  final MemberLaunchContext launchContext;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final registry = CliToolRegistryScope.of(context);
    final cubit = context.read<LaunchProfileCubit>();
    final team = LaunchProfileSelectors.teamById(cubit.state, launchContext.teamId);
    final member =
        LaunchProfileSelectors.memberById(team, launchContext.memberId);
    if (team == null || member == null) return const SizedBox.shrink();

    final presets = context
        .select<CliPresetsCubit, List<CliPreset>>((c) => c.state.presets);
    final catalogCli = memberCustomCatalogCli(team, member);
    final catalogDef = registry.tryGet(
      resolveMemberLaunch(
        team: team,
        member: member,
        globalPresets: presets,
      ).cli,
    );
    final providers = context
        .select<AppProviderCubit, List<AppProviderConfig>>(
          (c) => c.state.providersFor(catalogCli).toList(growable: false),
        );
    final resolved = resolveMemberLaunch(
      team: team,
      member: member,
      globalPresets: presets,
    );
    AppProviderConfig? selectedProvider;
    final prov = resolved.provider.trim();
    if (prov.isNotEmpty) {
      for (final p in providers) {
        if (p.id == prov) {
          selectedProvider = p;
          break;
        }
      }
    }
    final hidesModelPicker = workspaceCliHidesModelPicker(
      registry,
      resolved.cli,
      selectedProvider,
    );
    final configured = memberLaunchIsConfigured(
      team: team,
      member: member,
      registry: registry,
      presets: presets,
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
      presets: presets,
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
                label: Text(l10n.workspaceCliConfigure),
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
  required TeamProfile team,
  required TeamMemberConfig member,
  required LaunchProfileCubit cubit,
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

  final TeamProfile team;
  final TeamMemberConfig member;
  final LaunchProfileCubit cubit;

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
  late MemberLaunchConfigKind _configKind;

  @override
  void initState() {
    super.initState();
    _cliToken = widget.member.cli?.value ?? '';
    _providerId = widget.member.provider;
    _modelId = widget.member.model;
    _effortId = widget.member.effort;
    _configKind = memberLaunchConfigKind(widget.member);
  }

  CliTool _customCatalogCli(TeamProfile team) {
    if (team.teamMode == TeamMode.mixed && _cliToken.isNotEmpty) {
      return CliTool.decode(_cliToken);
    }
    return team.cli;
  }

  void _applyConfigKind(MemberLaunchConfigKind kind) {
    setState(() => _configKind = kind);
    switch (kind) {
      case MemberLaunchConfigKind.inheritTeam:
        widget.cubit.setMemberActivePreset(
          widget.member.id,
          TeamProfile.inheritPresetId,
        );
      case MemberLaunchConfigKind.custom:
        widget.cubit.setMemberActivePreset(widget.member.id, null);
        setState(() {
          _cliToken = widget.member.cli?.value ?? '';
          _providerId = widget.member.provider;
          _modelId = widget.member.model;
          _effortId = widget.member.effort;
        });
      case MemberLaunchConfigKind.preset:
        break;
    }
  }

  void _applyCatalogCliChange(String token) {
    setState(() {
      _cliToken = token;
      _providerId = '';
      _modelId = '';
      _effortId = '';
    });
  }

  /// Applies a preset choice when configuration type is [MemberLaunchConfigKind.preset].
  void _applyPresetChoice(String token, List<CliPreset> allPresets) {
    CliTool? syncCli;
    for (final preset in allPresets) {
      if (preset.id == token) {
        syncCli = preset.cli;
        break;
      }
    }
    widget.cubit.setMemberActivePreset(
      widget.member.id,
      token,
      syncCli: syncCli,
    );
    setState(() {
      _configKind = MemberLaunchConfigKind.preset;
      if (syncCli != null) _cliToken = syncCli.value;
    });
  }

  void _save() {
    if (_configKind == MemberLaunchConfigKind.custom) {
      final mixed = widget.team.teamMode == TeamMode.mixed;
      final nextCli = mixed && _cliToken.isNotEmpty
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
    }
    Navigator.of(context).pop();
  }

  bool _canSaveCustom(bool mixed) {
    if (_providerId.trim().isEmpty) return false;
    if (mixed && _cliToken.trim().isEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final dropdownDeco = AppDropdownDecorations.themed(context);
    final allPresets = context.watch<CliPresetsCubit>().state.presets;
    final team = context.watch<LaunchProfileCubit>().state.teams.firstWhere(
      (t) => t.id == widget.team.id,
      orElse: () => widget.team,
    );
    final member = team.members.cast<TeamMemberConfig?>().firstWhere(
      (m) => m!.id == widget.member.id,
      orElse: () => widget.member,
    )!;
    final isCustom = _configKind == MemberLaunchConfigKind.custom;
    final mixed = team.teamMode == TeamMode.mixed;
    final catalogCli = isCustom
        ? _customCatalogCli(team)
        : memberCustomCatalogCli(team, member);
    final eligiblePresetList = team.teamMode == TeamMode.mixed
        ? globalPresetPickerItems(allPresets)
        : teamPresetPickerItems(team: team, allPresets: allPresets);

    final presetDropdownItems = presetLaunchDropdownItems(
      mode: PresetLaunchPickerMode.presetOnly,
      eligiblePresets: eligiblePresetList,
    );
    final presetToken = memberLaunchPresetToken(member);
    final effectivePresetToken = presetDropdownItems.contains(presetToken)
        ? presetToken
        : (presetDropdownItems.isNotEmpty ? presetDropdownItems.first : '');

    final providers = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(catalogCli)
        .toList(growable: false);
    final mixedMemberCliItems = mixed
        ? registry.launchable.map((d) => d.id.value).toList(growable: false)
        : const <String>[];
    final providerState = context.watch<AppProviderCubit>().state;

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
                MemberLaunchConfigTypeField(
                  currentKind: _configKind,
                  decoration: dropdownDeco,
                  showDividerBelow:
                      _configKind == MemberLaunchConfigKind.custom,
                  onChanged: _applyConfigKind,
                ),
                if (_configKind == MemberLaunchConfigKind.inheritTeam)
                  MemberLaunchInheritSummary(
                    team: team,
                    presets: allPresets,
                    registry: registry,
                    providerState: providerState,
                  ),
                if (_configKind == MemberLaunchConfigKind.preset &&
                    presetDropdownItems.isNotEmpty)
                  MemberLaunchPresetField(
                    items: presetDropdownItems,
                    currentToken: effectivePresetToken,
                    eligiblePresets: eligiblePresetList,
                    registry: registry,
                    providerState: providerState,
                    decoration: dropdownDeco,
                    onChanged: (token) =>
                        _applyPresetChoice(token, allPresets),
                  ),
                if (isCustom)
                  CliLaunchCustomFields(
                    catalogCli: catalogCli,
                    providers: providers,
                    providerId: _providerId,
                    modelId: _modelId,
                    effortId: _effortId,
                    registry: registry,
                    cliFieldKind: mixed
                        ? CliLaunchCliFieldKind.mixedMember
                        : CliLaunchCliFieldKind.hidden,
                    mixedMemberCliItems: mixedMemberCliItems,
                    cliToken: _cliToken,
                    onMixedCliTokenChanged: _applyCatalogCliChange,
                    team: team,
                    member: member,
                    effortContext: CliLaunchEffortContext.member,
                    effortSubtitle: l10n.memberEffortLevelSubtitle,
                    effortAllowInherit: false,
                    effortTitle: l10n.memberEffortLevel,
                    dropdownKeyPrefix: 'member-launch',
                    decoration: dropdownDeco,
                    onProviderChanged: (value) => setState(() {
                      _providerId = value;
                      _modelId = '';
                      _effortId = '';
                    }),
                    onModelChanged: (value) => setState(() {
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
                    onEffortChanged: (value) =>
                        setState(() => _effortId = value.trim()),
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
              if (isCustom)
                FilledButton(
                  onPressed: _canSaveCustom(mixed) ? _save : null,
                  child: Text(l10n.save),
                )
              else
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.save),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
