import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../cubits/ai_feature_settings_cubit.dart';
import '../../../cubits/app_provider_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/ai_feature_setting.dart';
import '../../../models/cli_preset.dart';
import '../../../models/team_config.dart';
import '../../../models/team_generation_settings.dart';
import '../../../services/ai/ai_feature_setting_resolver.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/team_generation/team_generation_settings_store.dart';
import '../../../widgets/cli_launch_config/launch_four_tuple_picker.dart';
import '../../../widgets/compose/compose_model_preset_chip.dart';

/// Global generation settings editor: generator model (AI feature), team mode
/// (native/mixed), native CLI (native mode only), and the ranked model pool.
///
/// In native mode, non-matching rows are retained in storage and represented
/// by a hidden count. Generator and pool selections are stored as inline
/// CLI/provider/model/effort tuples.
Future<void> showWorkspaceLandingGenerateSettingsDialog(
  BuildContext context, {
  required List<CliPreset> presets,
  required AiFeatureSetting? generatorSetting,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _GenerateSettingsDialog(
      presets: presets,
      generatorSetting: generatorSetting,
    ),
  );
}

@visibleForTesting
SimpleLaunchFourTuple? constrainGenerateSettingsGenerator({
  required SimpleLaunchFourTuple? generator,
  required TeamMode teamMode,
  required CliTool nativeCli,
}) {
  if (teamMode == TeamMode.native && generator?.cli != nativeCli) return null;
  return generator;
}

class _GenerateSettingsDialog extends StatefulWidget {
  const _GenerateSettingsDialog({
    required this.presets,
    required this.generatorSetting,
  });

  final List<CliPreset> presets;
  final AiFeatureSetting? generatorSetting;

  @override
  State<_GenerateSettingsDialog> createState() =>
      _GenerateSettingsDialogState();
}

class _GenerateSettingsDialogState extends State<_GenerateSettingsDialog> {
  TeamMode _teamMode = TeamMode.mixed;
  CliTool _nativeCli = CliTool.claude;
  final List<_PoolRow> _rows = [];
  final _store = TeamGenerationSettingsStore();
  SimpleLaunchFourTuple? _generator;
  bool _generatorInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_generatorInitialized) return;
    _generatorInitialized = true;
    final stored = widget.generatorSetting;
    if (stored == null) return;
    final resolved = resolveAiFeatureSetting(
      stored: stored,
      appProviders: context.read<AppProviderCubit>().state,
      registry: _registry,
      globalPresets: widget.presets,
    );
    _generator = SimpleLaunchFourTuple(
      cli: resolved.cli,
      providerId: resolved.providerId,
      modelId: resolved.model,
      effort: resolved.effort,
    );
  }

  Future<void> _loadInitial() async {
    final loaded = await _store.load();
    final settings = hydrateTeamGenerationSettings(
      settings: loaded,
      presets: widget.presets,
    );
    if (!mounted) return;
    final nativeClis = _nativeCliItems;
    setState(() {
      _teamMode = settings.teamMode;
      _nativeCli = nativeClis.contains(settings.nativeCli)
          ? settings.nativeCli
          : (nativeClis.firstOrNull ?? CliTool.claude);
      _generator = constrainGenerateSettingsGenerator(
        generator: _generator,
        teamMode: _teamMode,
        nativeCli: _nativeCli,
      );
      _rows
        ..clear()
        ..addAll([
          for (final entry in settings.modelPool)
            _PoolRow(
              id: entry.id,
              cli: entry.cli,
              provider: entry.provider,
              model: entry.model,
              effort: entry.effort,
              description: entry.description,
              tags: [...entry.tags],
            ),
        ]);
    });
  }

  CliToolRegistry get _registry =>
      CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();

  List<CliTool> get _launchableCliItems =>
      _registry.launchable.map((definition) => definition.id).toList();

  List<CliTool> get _nativeCliItems => _registry.nativeTeamLaunchable
      .map((definition) => definition.id)
      .toList();

  List<CliTool> get _pickerCliItems =>
      _teamMode == TeamMode.native ? [_nativeCli] : _launchableCliItems;

  bool _isVisibleRow(_PoolRow row) =>
      _teamMode != TeamMode.native || row.cli == _nativeCli;

  bool _isConfiguredRow(_PoolRow row) =>
      row.id.trim().isNotEmpty &&
      row.provider.trim().isNotEmpty &&
      row.model.trim().isNotEmpty;

  int get _hiddenCount {
    if (_teamMode != TeamMode.native) return 0;
    return _rows.where((row) => !_isVisibleRow(row)).length;
  }

  AiFeatureSetting? get _draftGeneratorSetting {
    final generator = constrainGenerateSettingsGenerator(
      generator: _generator,
      teamMode: _teamMode,
      nativeCli: _nativeCli,
    );
    if (generator == null) return null;
    return AiFeatureSetting(
      activePresetId: null,
      cli: generator.cli,
      providerId: generator.providerId,
      model: generator.modelId,
      effort: generator.effort,
    );
  }

  bool get _canSave {
    return _effectiveRows.isNotEmpty &&
        aiFeatureIsConfigured(
          stored: _draftGeneratorSetting,
          registry: _registry,
          appProviders: context.read<AppProviderCubit>().state,
          globalPresets: widget.presets,
        );
  }

  /// Rows surviving the native filter; the stored pool keeps everything.
  List<_PoolRow> get _effectiveRows =>
      _rows.where(_isVisibleRow).where(_isConfiguredRow).toList();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return AlertDialog(
      title: Text(l10n.teamGenerateSettingsTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.teamGenerateGeneratorModel, style: styles.mdSemibold),
              const SizedBox(height: 4),
              LaunchFourTuplePicker(
                value: _generator,
                cliItems: _pickerCliItems,
                presets: widget.presets,
                onChanged: (value) => setState(() => _generator = value),
                showManagePresets: true,
                showSavePreset: false,
                emptyLabel: l10n.teamGenerateErrorAiNotConfigured,
              ),
              const SizedBox(height: 16),

              Text(l10n.teamGenerateTeamMode, style: styles.mdSemibold),
              const SizedBox(height: 4),
              SegmentedButton<TeamMode>(
                segments: [
                  ButtonSegment(
                    value: TeamMode.native,
                    label: Text(l10n.teamGenerateNative),
                  ),
                  ButtonSegment(
                    value: TeamMode.mixed,
                    label: Text(l10n.teamGenerateMixed),
                  ),
                ],
                selected: {_teamMode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _teamMode = selection.first;
                    if (_teamMode == TeamMode.native) {
                      final nativeClis = _nativeCliItems;
                      final firstMatching = _rows
                          .where((row) => nativeClis.contains(row.cli))
                          .firstOrNull;
                      if (firstMatching != null) {
                        _nativeCli = firstMatching.cli;
                      } else if (!nativeClis.contains(_nativeCli)) {
                        _nativeCli = nativeClis.firstOrNull ?? CliTool.claude;
                      }
                      _generator = constrainGenerateSettingsGenerator(
                        generator: _generator,
                        teamMode: _teamMode,
                        nativeCli: _nativeCli,
                      );
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              if (_teamMode == TeamMode.native) ...[
                DropdownButtonFormField<CliTool>(
                  initialValue: _nativeCli,
                  decoration: InputDecoration(
                    labelText: l10n.teamGenerateNativeCli,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final tool in _nativeCliItems)
                      DropdownMenuItem(value: tool, child: Text(tool.value)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _nativeCli = value;
                      _generator = constrainGenerateSettingsGenerator(
                        generator: _generator,
                        teamMode: _teamMode,
                        nativeCli: _nativeCli,
                      );
                    });
                  },
                ),
              ],
              const SizedBox(height: 16),

              Text(l10n.teamGenerateModelPool, style: styles.mdSemibold),
              if (_teamMode == TeamMode.native && _hiddenCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.teamGenerateHiddenPresets(_hiddenCount),
                  style: styles.smMedium.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 8),
              for (var i = 0; i < _rows.length; i++)
                if (_isVisibleRow(_rows[i])) _poolRowTile(context, i),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addModel,
                icon: const Icon(Icons.add),
                label: Text(l10n.teamGenerateAddModel),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.teamGenerateCapabilityNote,
                style: styles.smMedium.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _canSave ? () => _save(context) : null,
          child: Text(MaterialLocalizations.of(context).saveButtonLabel),
        ),
      ],
    );
  }

  Widget _poolRowTile(BuildContext context, int index) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final row = _rows[index];
    final invalid = !_isConfiguredRow(row);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: invalid
              ? cs.errorContainer.withValues(alpha: 0.35)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: invalid
                ? cs.error
                : cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${index + 1}.', style: styles.smMedium),
                const SizedBox(width: 6),
                Expanded(
                  child: LaunchFourTuplePicker(
                    value: invalid
                        ? null
                        : SimpleLaunchFourTuple(
                            cli: row.cli,
                            providerId: row.provider,
                            modelId: row.model,
                            effort: row.effort,
                          ),
                    cliItems: _pickerCliItems,
                    presets: widget.presets,
                    onChanged: (value) {
                      setState(() {
                        row.cli = value.cli;
                        row.provider = value.providerId;
                        row.model = value.modelId;
                        row.effort = value.effort;
                      });
                    },
                    showManagePresets: true,
                    showSavePreset: false,
                    emptyLabel: l10n.teamGenerateAddModel,
                  ),
                ),
                IconButton(
                  tooltip: l10n.teamGenerateMoveUp,
                  onPressed: index == 0
                      ? null
                      : () => setState(() {
                          final tmp = _rows[index - 1];
                          _rows[index - 1] = _rows[index];
                          _rows[index] = tmp;
                        }),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: l10n.teamGenerateMoveDown,
                  onPressed: index == _rows.length - 1
                      ? null
                      : () => setState(() {
                          final tmp = _rows[index + 1];
                          _rows[index + 1] = _rows[index];
                          _rows[index] = tmp;
                        }),
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
                IconButton(
                  tooltip: l10n.teamGenerateRemove,
                  onPressed: () => setState(() => _rows.removeAt(index)),
                  icon: Icon(
                    Icons.remove_circle_outline,
                    size: 18,
                    color: cs.error,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: row.description,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.teamGenerateDescription,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => row.description = value,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: row.tags.join(', '),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.teamGenerateTags,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      row.tags = [
                        for (final tag in value.split(','))
                          if (tag.trim().isNotEmpty) tag.trim(),
                      ];
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addModel() async {
    final selected = await showDialog<SimpleLaunchFourTuple>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.l10n.teamGenerateAddModel),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LaunchFourTuplePicker(
              value: null,
              cliItems: _pickerCliItems,
              presets: widget.presets,
              onChanged: (value) => Navigator.of(dialogContext).pop(value),
              showManagePresets: true,
              showSavePreset: false,
              emptyLabel: context.l10n.teamGenerateAddModel,
            ),
          ),
        ],
      ),
    );
    if (selected == null) return;
    setState(() {
      _rows.add(
        _PoolRow(
          id: const Uuid().v4(),
          cli: selected.cli,
          provider: selected.providerId,
          model: selected.modelId,
          effort: selected.effort,
        ),
      );
    });
  }

  Future<void> _save(BuildContext context) async {
    final generator = constrainGenerateSettingsGenerator(
      generator: _generator,
      teamMode: _teamMode,
      nativeCli: _nativeCli,
    );
    if (generator == null) return;
    await context.read<AiFeatureSettingsCubit>().updateSetting(
      AiFeatureId.teamGenerate,
      AiFeatureSetting(
        activePresetId: null,
        cli: generator.cli,
        providerId: generator.providerId,
        model: generator.modelId,
        effort: generator.effort,
      ),
    );
    await _store.save(
      TeamGenerationSettings(
        teamMode: _teamMode,
        nativeCli: _nativeCli,
        modelPool: _rows.map((row) => row.toEntry()).toList(),
      ),
    );
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _PoolRow {
  _PoolRow({
    required this.id,
    required this.cli,
    required this.provider,
    required this.model,
    this.effort = '',
    this.description = '',
    List<String>? tags,
  }) : tags = tags ?? [];

  String id;
  CliTool cli;
  String provider;
  String model;
  String effort;
  String description;
  List<String> tags;

  GenerateModelPoolEntry toEntry() => GenerateModelPoolEntry(
    id: id,
    cli: cli,
    provider: provider,
    model: model,
    effort: effort,
    description: description,
    tags: tags,
  );
}
