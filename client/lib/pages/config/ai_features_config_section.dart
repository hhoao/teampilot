import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/ai_feature_settings_cubit.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/ai_feature_setting.dart';
import '../../models/app_provider_config.dart';
import '../../services/ai/ai_feature_setting_resolver.dart';
import '../../services/cli/registry/capabilities/provider_model_capability.dart';
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
import '../home_workspace/project/config/project_cli_effort_helpers.dart';

/// Global "AI Features" settings: per-feature CLI/provider/model/effort.
class AiFeaturesConfigWorkspace extends StatelessWidget {
  const AiFeaturesConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AiFeatureSettingsCubit, AiFeatureSettingsState>(
      builder: (context, state) {
        return SingleChildScrollView(
          child: SettingsSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showHeading) ...[
                  SettingsGroupHeader(title: l10n.aiFeatures),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      l10n.aiFeaturesPageSubtitle,
                      style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                AiFeatureConfigRow(
                  feature: AiFeatureId.commitMessage,
                  title: l10n.aiFeatureCommitMessageTitle,
                  intro: l10n.aiFeatureCommitMessageSubtitle,
                  icon: Icons.auto_awesome_outlined,
                  setting: state.settingFor(AiFeatureId.commitMessage),
                  showDividerBelow: true,
                ),
                AiFeatureConfigRow(
                  feature: AiFeatureId.teamGenerate,
                  title: l10n.aiFeatureTeamGenerateTitle,
                  intro: l10n.aiFeatureTeamGenerateSubtitle,
                  icon: Icons.groups_outlined,
                  setting: state.settingFor(AiFeatureId.teamGenerate),
                  showDividerBelow: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AiFeatureConfigRow extends StatelessWidget {
  const AiFeatureConfigRow({
    required this.feature,
    required this.title,
    required this.intro,
    required this.icon,
    required this.setting,
    this.showDividerBelow = true,
    super.key,
  });

  final AiFeatureId feature;
  final String title;
  final String intro;
  final IconData icon;
  final AiFeatureSetting? setting;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final registry = CliToolRegistryScope.of(context);
    final appProviders = context.watch<AppProviderCubit>().state;

    final resolved = resolveAiFeatureSetting(
      stored: setting,
      appProviders: appProviders,
      registry: registry,
    );
    final cli = resolved.cli;
    final cliDef = registry.tryGet(cli);
    final providers = aiFeatureProvidersForCli(cli, appProviders, registry);
    final provider =
        providers.where((p) => p.id == resolved.providerId).firstOrNull;
    final hidesModelPicker = projectCliHidesModelPicker(registry, cli, provider);
    final configured = aiFeatureIsConfigured(
      resolved: resolved,
      registry: registry,
      provider: provider,
    );
    final configLine = aiFeatureConfigLine(
      l10n: l10n,
      registry: registry,
      configured: configured,
      resolved: resolved,
      provider: provider,
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
              configured && provider != null && provider.icon.isNotEmpty
                  ? ProviderBrandIcon.fromConfig(
                      provider,
                      size: 40,
                      borderRadius: 10,
                    )
                  : cliDef != null
                  ? CliBrandIcon(
                      cli: cli,
                      definition: cliDef,
                      label: cliDisplayName(cliDef, l10n),
                      size: 40,
                      borderRadius: 10,
                    )
                  : _FeatureIcon(icon: icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
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
                    Text(
                      intro,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: styles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                onPressed: () => _openConfigureDialog(
                  context,
                  feature: feature,
                  title: title,
                  initial: resolved,
                ),
                icon: const Icon(Icons.tune, size: AppIconSizes.sm),
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

class _FeatureIcon extends StatelessWidget {
  const _FeatureIcon({required this.icon});

  final IconData icon;

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
      child: Icon(icon, size: 22, color: cs.onSurfaceVariant),
    );
  }
}

Future<void> _openConfigureDialog(
  BuildContext context, {
  required AiFeatureId feature,
  required String title,
  required AiFeatureSetting initial,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AiFeatureConfigureDialog(
      feature: feature,
      title: title,
      initial: initial,
    ),
  );
}

class AiFeatureConfigureDialog extends StatefulWidget {
  const AiFeatureConfigureDialog({
    required this.feature,
    required this.title,
    required this.initial,
    super.key,
  });

  final AiFeatureId feature;
  final String title;
  final AiFeatureSetting initial;

  @override
  State<AiFeatureConfigureDialog> createState() => _AiFeatureConfigureDialogState();
}

class _AiFeatureConfigureDialogState extends State<AiFeatureConfigureDialog> {
  late CliTool _cli;
  late String _providerId;
  late String _modelId;
  late String _effortId;

  @override
  void initState() {
    super.initState();
    _cli = widget.initial.cli;
    _providerId = widget.initial.providerId;
    _modelId = widget.initial.model;
    _effortId = widget.initial.effort;
  }

  AppProviderConfig? _selectedProvider(Iterable<AppProviderConfig> providers) {
    for (final provider in providers) {
      if (provider.id == _providerId) return provider;
    }
    return null;
  }

  Future<void> _save() async {
    await context.read<AiFeatureSettingsCubit>().updateSetting(
      widget.feature,
      AiFeatureSetting(
        cli: _cli,
        providerId: _providerId,
        model: _modelId,
        effort: _effortId,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _applyCli(CliTool nextCli) {
    final registry = CliToolRegistryScope.of(context);
    final appProviders = context.read<AppProviderCubit>().state;
    final nextProviders =
        aiFeatureProvidersForCli(nextCli, appProviders, registry);
    final nextProviderId = _defaultProviderIdForCli(
      nextCli,
      nextProviders,
      appProviders,
    );
    final nextProvider =
        nextProviders.where((p) => p.id == nextProviderId).firstOrNull;
    final modelCap = registry.capability<ProviderModelCapability>(nextCli);
    final nextModel =
        modelCap?.defaultModel(
          provider: nextProvider,
          providerId: nextProviderId,
        ) ??
        '';
    setState(() {
      _cli = nextCli;
      _providerId = nextProviderId;
      _modelId = nextModel;
      _effortId = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final dropdownDeco = AppDropdownDecorations.themed(context);
    final appProviders = context.watch<AppProviderCubit>().state;
    final providers = aiFeatureProvidersForCli(_cli, appProviders, registry);
    final providerIds = providers.map((p) => p.id).toList();
    final selectedProvider = _selectedProvider(providers);
    final hideModelPicker = projectCliHidesModelPicker(
      registry,
      _cli,
      selectedProvider,
    );
    final showEffortPicker = projectCliShowsEffortPicker(
      registry: registry,
      cli: _cli,
      provider: selectedProvider,
      model: _modelId,
    );
    final cliItems = [
      CliTool.claude,
      CliTool.codex,
      CliTool.flashskyai,
      CliTool.cursor,
      CliTool.opencode,
    ];

    return AppDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: widget.title),
          const SizedBox(height: 16),
          SettingsSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsGroupHeader(title: l10n.aiFeatures),
              SettingsLabeledRow(
                title: l10n.aiFeatureCliLabel,
                trailing: _aiFeatureDialogDropdown(
                  AppDropdownField<CliTool>(
                    items: cliItems,
                    initialItem: _cli,
                    decoration: dropdownDeco,
                    itemLabel: (c) {
                      final def = registry.tryGet(c);
                      return def == null ? c.value : cliDisplayName(def, l10n);
                    },
                    onChanged: (c) {
                      if (c == null || c == _cli) return;
                      _applyCli(c);
                    },
                  ),
                ),
                showDividerBelow: providers.isNotEmpty,
              ),
              if (providers.isEmpty)
                SettingsLabeledRow(
                  title: l10n.provider,
                  trailing: Text(
                    l10n.onboardingDefaultProviderEmpty,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  showDividerBelow: false,
                )
              else ...[
                SettingsLabeledRow(
                  title: l10n.provider,
                  trailing: _aiFeatureDialogDropdown(
                    AppDropdownField<String>(
                      key: ValueKey(
                        'ai-feature-dialog-provider-${widget.feature.key}-$_providerId',
                      ),
                      items: providerIds,
                      initialItem: _providerId.isEmpty ? null : _providerId,
                      hintText: l10n.selectProvider,
                      decoration: dropdownDeco,
                      onChanged: (value) {
                        if (value == null || value.isEmpty) return;
                        final nextProvider =
                            providers.where((p) => p.id == value).firstOrNull;
                        final modelCap =
                            registry.capability<ProviderModelCapability>(_cli);
                        final nextModel =
                            modelCap?.defaultModel(
                              provider: nextProvider,
                              providerId: value,
                            ) ??
                            '';
                        setState(() {
                          _providerId = value;
                          _modelId = nextModel;
                          _effortId = '';
                        });
                      },
                      itemBuilder: providerDropdownItemBuilder(
                        providers: providers,
                        labelFor: (id) =>
                            providers
                                .where((p) => p.id == id)
                                .map((p) => p.name)
                                .firstOrNull ??
                            id,
                      ),
                    ),
                  ),
                  showDividerBelow: !hideModelPicker || showEffortPicker,
                ),
                if (!hideModelPicker)
                  SettingsLabeledRow(
                    title: l10n.aiFeatureModelLabel,
                    trailing: _aiFeatureDialogDropdown(
                      ProviderModelPickerField(
                        key: ValueKey(
                          'ai-feature-dialog-model-$_providerId-$_modelId',
                        ),
                        cli: _cli,
                        providerId: _providerId,
                        provider: selectedProvider,
                        value: _modelId,
                        hintText: l10n.selectModel,
                        decoration: dropdownDeco,
                        onChanged: (value) => setState(() {
                          _modelId = value.trim();
                          if (!projectCliShowsEffortPicker(
                            registry: registry,
                            cli: _cli,
                            provider: selectedProvider,
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
                    title: l10n.aiFeatureEffortLabel,
                    subtitle: l10n.projectCliEffortLevelSubtitle,
                    trailing: _aiFeatureDialogDropdown(
                      CliEffortPickerField(
                        key: ValueKey(
                          'ai-feature-dialog-effort-$_providerId-$_modelId-$_effortId',
                        ),
                        cli: _cli,
                        value: _effortId,
                        provider: selectedProvider,
                        model: _modelId,
                        allowInherit: true,
                        inheritLabel: l10n.projectCliEffortInheritHint,
                        decoration: dropdownDeco,
                        onChanged: (value) =>
                            setState(() => _effortId = value.trim()),
                      ),
                    ),
                    showDividerBelow: false,
                  ),
              ],
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

const _aiFeatureDialogDropdownMinWidth = 180.0;

Widget _aiFeatureDialogDropdown(Widget child) {
  return ConstrainedBox(
    constraints: const BoxConstraints(minWidth: _aiFeatureDialogDropdownMinWidth),
    child: child,
  );
}

String _defaultProviderIdForCli(
  CliTool cli,
  List<AppProviderConfig> providers,
  AppProviderState appProviders,
) {
  final global = appProviders.selectedProviderIdByCli[cli];
  if (global != null && providers.any((p) => p.id == global)) {
    return global;
  }
  return providers.firstOrNull?.id ?? '';
}
