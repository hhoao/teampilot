import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../../cubits/app_provider_cubit.dart';
import '../../../../cubits/project_profile_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../models/project_profile.dart';
import '../../../../services/cli/registry/cli_display_name.dart';
import '../../../../services/cli/registry/cli_tool_definition.dart';
import '../../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../../widgets/dropdown/app_dropdown_field.dart';
import '../../../../widgets/app_provider/brand_dropdown_rows.dart';
import '../../../../widgets/app_provider/cli_effort_picker_field.dart';
import '../../../../widgets/app_provider/provider_model_picker_field.dart';
import '../../../../widgets/app_provider/provider_brand_icon.dart';
import '../../../../widgets/cli/cli_brand_icon.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';
import 'project_cli_config_helpers.dart';
import 'project_cli_effort_helpers.dart';

/// Provider/model defaults per launchable CLI (cc-switch–style list rows).
class ProjectCliConfigList extends StatelessWidget {
  const ProjectCliConfigList({
    required this.profile,
    required this.cubit,
    super.key,
  });

  final ProjectProfile profile;
  final ProjectProfileCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final launchable = registry.launchable.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));

    return SettingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsGroupHeader(title: l10n.projectCliDefaultsTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              l10n.projectCliDefaultsSubtitle,
              style: AppTextStyles.of(context).bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          for (var i = 0; i < launchable.length; i++)
            ProjectCliConfigRow(
              definition: launchable[i],
              profile: profile,
              supportsProviderCatalog: projectCliSupportsProviderCatalog(
                launchable[i].id,
                registry,
              ),
              showDividerBelow: i < launchable.length - 1,
              onConfigure: projectCliSupportsProviderCatalog(
                launchable[i].id,
                registry,
              )
                  ? () => _openConfigureDialog(
                      context,
                      cli: launchable[i].id,
                      profile: profile,
                      cubit: cubit,
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

class ProjectCliConfigRow extends StatelessWidget {
  const ProjectCliConfigRow({
    required this.definition,
    required this.profile,
    required this.supportsProviderCatalog,
    this.showDividerBelow = true,
    this.onConfigure,
    super.key,
  });

  final CliToolDefinition definition;
  final ProjectProfile profile;
  final bool supportsProviderCatalog;
  final bool showDividerBelow;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final cli = definition.id;
    final title = cliDisplayName(definition, l10n);

    final providers = supportsProviderCatalog
        ? context.watch<AppProviderCubit>().state.providersFor(cli)
        : const <AppProviderConfig>[];
    final selectedProvider = projectCliSelectedProvider(
      profile,
      cli,
      providers,
    );
    final registry = CliToolRegistryScope.of(context);
    final configured = projectCliIsConfigured(
      profile,
      cli,
      registry,
      selectedProvider: selectedProvider,
      supportsProviderCatalog: supportsProviderCatalog,
    );
    final model = projectCliModelId(profile, cli);
    final effort = projectCliEffortId(profile, cli);
    final subtitle = _subtitle(
      l10n: l10n,
      configured: configured,
      supportsProviderCatalog: supportsProviderCatalog,
      selectedProvider: selectedProvider,
      model: model,
      effort: effort,
      hidesModelPicker: projectCliHidesModelPicker(
        registry,
        cli,
        selectedProvider,
      ),
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
                  : CliBrandIcon(
                      cli: cli,
                      definition: definition,
                      label: title,
                      size: 40,
                      borderRadius: 10,
                    ),
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
                      subtitle,
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
              if (onConfigure != null)
                OutlinedButton.icon(
                  onPressed: onConfigure,
                  icon: const Icon(Icons.add, size: AppIconSizes.sm),
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

  String _subtitle({
    required AppLocalizations l10n,
    required bool configured,
    required bool supportsProviderCatalog,
    required AppProviderConfig? selectedProvider,
    required String model,
    required String effort,
    required bool hidesModelPicker,
  }) {
    if (!supportsProviderCatalog) {
      return l10n.projectCliNoProviderCatalog;
    }
    if (!configured) return l10n.projectCliNotConfiguredHint;
    final providerName = selectedProvider?.name.trim() ?? '';
    if (providerName.isEmpty) return l10n.projectCliConfigured;
    final modelLabel = model.trim();
    final effortLabel = effort.trim();
    if (modelLabel.isEmpty && hidesModelPicker) {
      if (effortLabel.isEmpty) return providerName;
      return '$providerName · $effortLabel';
    }
    if (modelLabel.isEmpty) {
      if (effortLabel.isEmpty) return providerName;
      return '$providerName · $effortLabel';
    }
    if (effortLabel.isEmpty) {
      return l10n.projectCliConfigSummary(providerName, modelLabel);
    }
    return '${l10n.projectCliConfigSummary(providerName, modelLabel)} · $effortLabel';
  }
}

Future<void> _openConfigureDialog(
  BuildContext context, {
  required CliTool cli,
  required ProjectProfile profile,
  required ProjectProfileCubit cubit,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => ProjectCliConfigureDialog(
      cli: cli,
      profile: profile,
      cubit: cubit,
    ),
  );
}

class ProjectCliConfigureDialog extends StatefulWidget {
  const ProjectCliConfigureDialog({
    required this.cli,
    required this.profile,
    required this.cubit,
    super.key,
  });

  final CliTool cli;
  final ProjectProfile profile;
  final ProjectProfileCubit cubit;

  @override
  State<ProjectCliConfigureDialog> createState() =>
      _ProjectCliConfigureDialogState();
}

class _ProjectCliConfigureDialogState extends State<ProjectCliConfigureDialog> {
  late String _providerId;
  late String _modelId;
  late String _effortId;

  @override
  void initState() {
    super.initState();
    _providerId = projectCliProviderId(widget.profile, widget.cli);
    _modelId = projectCliModelId(widget.profile, widget.cli);
    _effortId = projectCliEffortId(widget.profile, widget.cli);
  }

  AppProviderConfig? _selectedProvider(Iterable<AppProviderConfig> providers) {
    for (final provider in providers) {
      if (provider.id == _providerId) return provider;
    }
    return null;
  }

  Future<void> _save() async {
    await widget.cubit.setCliDefaults(
      widget.cli,
      provider: _providerId,
      model: _modelId,
      effort: _effortId,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final def = registry.tryGet(widget.cli);
    final title = def == null
        ? widget.cli.value
        : cliDisplayName(def, l10n);
    final dropdownDeco = AppDropdownDecorations.themed(context);
    final providers = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(widget.cli)
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
      widget.cli,
      selectedProvider,
    );
    final showEffortPicker = projectCliShowsEffortPicker(
      registry: registry,
      cli: widget.cli,
      provider: selectedProvider,
      model: _modelId,
    );

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: SettingsSurfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGroupHeader(title: l10n.projectCliProviderModelTitle),
              SettingsLabeledStackedRow(
                title: l10n.provider,
                body: AppDropdownField<String>(
                key: ValueKey(
                  'project-cli-provider-${widget.cli.value}-$_providerId',
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
              showDividerBelow: hideModelPicker || showEffortPicker,
            ),
            if (!hideModelPicker)
              SettingsLabeledStackedRow(
                title: l10n.model,
                body: ProviderModelPickerField(
                  key: ValueKey(
                    'project-cli-model-$_providerId-$_modelId',
                  ),
                  cli: widget.cli,
                  providerId: _providerId,
                  provider: selectedProvider,
                  value: _modelId,
                  hintText: l10n.selectModel,
                  decoration: dropdownDeco,
                  onChanged: (value) => setState(() {
                    _modelId = value.trim();
                    if (!projectCliShowsEffortPicker(
                      registry: registry,
                      cli: widget.cli,
                      provider: selectedProvider,
                      model: _modelId,
                    )) {
                      _effortId = '';
                    }
                  }),
                ),
                showDividerBelow: showEffortPicker,
              ),
            if (showEffortPicker)
              SettingsLabeledStackedRow(
                title: l10n.projectCliEffortLevel,
                subtitle: l10n.projectCliEffortLevelSubtitle,
                body: CliEffortPickerField(
                  key: ValueKey(
                    'project-cli-effort-$_providerId-$_modelId-$_effortId',
                  ),
                  cli: widget.cli,
                  value: _effortId,
                  provider: selectedProvider,
                  model: _modelId,
                  allowInherit: true,
                  inheritLabel: l10n.projectCliEffortInheritHint,
                  decoration: dropdownDeco,
                  onChanged: (value) =>
                      setState(() => _effortId = value.trim()),
                ),
                showDividerBelow: false,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _providerId.trim().isEmpty ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
