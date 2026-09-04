import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../pages/home_workspace/workspace/config/cli_preset_edit_dialog.dart';
import '../../pages/home_workspace/workspace/config/cli_presets_manage_dialog.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../cli/cli_brand_icon.dart';
import '../compose/compose_model_preset_chip.dart';
import '../compose/simple_custom_launch_dialog.dart';

SimpleLaunchFourTuple? tupleFromCascadeSelection({
  required Object? value,
  required List<CliPreset> presets,
}) {
  if (value is String && value.isNotEmpty) {
    for (final preset in presets) {
      if (preset.id == value) {
        return SimpleLaunchFourTuple(
          cli: preset.cli,
          providerId: preset.provider,
          modelId: preset.model,
          effort: preset.effort,
        );
      }
    }
  }
  return decodeComposeCascadeValue(value);
}

class LaunchFourTuplePicker extends StatefulWidget {
  const LaunchFourTuplePicker({
    required this.value,
    required this.cliItems,
    required this.presets,
    required this.onChanged,
    this.showManagePresets = true,
    this.showSavePreset = false,
    this.emptyLabel,
    super.key,
  });

  final SimpleLaunchFourTuple? value;
  final List<CliTool> cliItems;
  final List<CliPreset> presets;
  final ValueChanged<SimpleLaunchFourTuple> onChanged;
  final bool showManagePresets;
  final bool showSavePreset;
  final String? emptyLabel;

  @override
  State<LaunchFourTuplePicker> createState() => _LaunchFourTuplePickerState();
}

class _LaunchFourTuplePickerState extends State<LaunchFourTuplePicker> {
  CascadeCatalogListenable? _catalog;
  CliToolRegistry? _registry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
    if (!identical(registry, _registry)) {
      _catalog?.dispose();
      _registry = registry;
      _catalog = CascadeCatalogListenable(registry: registry);
    }
    _catalog!.attach(widget.cliItems);
  }

  @override
  void didUpdateWidget(covariant LaunchFourTuplePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _catalog?.attach(widget.cliItems);
  }

  @override
  void dispose() {
    _catalog?.dispose();
    super.dispose();
  }

  Future<void> _onSelected(
    Object? value,
    List<CliPreset> availablePresets,
  ) async {
    final tuple = tupleFromCascadeSelection(
      value: value,
      presets: availablePresets,
    );
    if (tuple != null) {
      widget.onChanged(tuple);
      return;
    }
    if (value is CascadeCustomModelRequest) {
      final modelId = await showComposeCustomModelIdDialog(
        context,
        title: context.l10n.composeCascadeCustomModelIdTitle,
        confirmLabel: context.l10n.confirm,
        initial: widget.value?.modelId ?? '',
      );
      if (!mounted || modelId == null || modelId.isEmpty) return;
      widget.onChanged(
        SimpleLaunchFourTuple(
          cli: value.cli,
          providerId: value.providerId,
          modelId: modelId,
          effort: widget.value?.effort ?? '',
        ),
      );
      return;
    }
    if (value == ComposeModelPresetChipAction.manage) {
      await showDialog<void>(
        context: context,
        builder: (_) => const CliPresetsManageDialog(),
      );
      return;
    }
    if (value == ComposeModelPresetChipAction.savePreset) {
      final current = widget.value;
      if (current == null) return;
      await showDialog<void>(
        context: context,
        builder: (_) => CliPresetEditDialog(
          draft: CliPreset(
            id: '',
            name: '',
            cli: current.cli,
            provider: current.providerId,
            model: current.modelId,
            effort: current.effort,
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    if (catalog == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: catalog,
      builder: (context, _) => _buildPicker(context),
    );
  }

  Widget _buildPicker(BuildContext context) {
    final l10n = context.l10n;
    final registry = _registry!;
    final allowedClis = widget.cliItems.toSet();
    final availablePresets = widget.presets
        .where((preset) => allowedClis.contains(preset.cli))
        .toList(growable: false);
    final providerState = context.watch<AppProviderCubit>().state;
    final groups = resolveComposeCascadeCliGroups(
      registry: registry,
      providersByCli: {
        for (final cli in widget.cliItems)
          cli: providerState.providersFor(cli).toList(growable: false),
      },
      cliItems: widget.cliItems,
    );
    final emptyLabel = widget.emptyLabel ?? l10n.workspaceChatLandingUsePreset;
    final label = simpleLaunchChipLabel(
      presetName: null,
      cli: widget.value?.cli,
      provider: widget.value?.providerId,
      model: widget.value?.modelId,
      emptyLabel: emptyLabel,
    );
    final iconCli =
        widget.value?.cli ??
        (widget.cliItems.isEmpty ? CliTool.claude : widget.cliItems.first);
    final specs = buildComposeModelCascadeMenuSpecs(
      presets: availablePresets,
      selectedPresetId: null,
      emptyHintLabel: l10n.workspaceCliPresetsEmptyHint,
      emptyProvidersLabel: l10n.composeCascadeNoProviders,
      presetsLabel: l10n.composeCascadePresets,
      defaultEffortLabel: l10n.composeCascadeDefaultEffort,
      customModelIdLabel: l10n.composeCascadeCustomModelId,
      noModelsLabel: l10n.composeCascadeNoModels,
      savePresetLabel: l10n.composeCascadeSavePreset,
      managePresetsLabel: l10n.workspaceCliAddPresetTitle,
      cliGroups: groups,
      groupByCli: widget.cliItems.length > 1,
      showSavePreset: widget.showSavePreset,
      showManagePresets: widget.showManagePresets,
      onModelsOpened: (cli, providerId, provider) => unawaited(
        refreshComposeCascadeCatalog(
          context,
          cli: cli,
          providerId: providerId,
          provider: provider,
        ),
      ),
    );
    final cs = Theme.of(context).colorScheme;

    return TpActionMenuButton(
      minWidth: 120,
      specs: specs,
      onSelected: (value) => unawaited(_onSelected(value, availablePresets)),
      triggerBuilder: (context, controller) => TpHover(
        backgroundColor: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        onTap: controller.isOpen ? controller.close : controller.open,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CliBrandIcon(
                cli: iconCli,
                size: 20,
                borderRadius: 4,
                showBorder: false,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).mdColored(cs.onSurface),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
