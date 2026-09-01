import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/ai_feature_setting.dart';
import '../../../models/cli_preset.dart';
import '../../../models/team_config.dart';
import '../../../models/team_generation_settings.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/team_generation/team_generation_settings_store.dart';

/// Global generation settings editor: generator model (AI feature), team mode
/// (native/mixed), native CLI (native mode only), and the ranked model pool.
///
/// In native mode, non-matching valid rows are retained in storage and shown
/// as a hidden count; broken references stay visible in error color with a
/// removal action. Save is disabled while the effective pool is empty, a
/// visible reference is invalid, or generator configuration is missing.
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

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final settings = await _store.load();
    if (!mounted) return;
    setState(() {
      _teamMode = settings.teamMode;
      _nativeCli = settings.nativeCli;
      _rows
        ..clear()
        ..addAll([
          for (final entry in settings.modelPool)
            _PoolRow(
              presetId: entry.presetId,
              description: entry.description,
              tags: [...entry.tags],
            ),
        ]);
    });
  }

  List<CliPreset> get _visiblePresets {
    if (_teamMode != TeamMode.native) return widget.presets;
    return [
      for (final preset in widget.presets)
        if (preset.cli == _nativeCli) preset,
    ];
  }

  int get _hiddenCount {
    if (_teamMode != TeamMode.native) return 0;
    final validNonMatching = _rows
        .where((row) => _presetFor(row.presetId) != null)
        .where((row) => _presetFor(row.presetId)!.cli != _nativeCli)
        .length;
    return validNonMatching;
  }

  CliPreset? _presetFor(String presetId) {
    final id = presetId.trim();
    if (id.isEmpty) return null;
    return widget.presets.where((preset) => preset.id == id).firstOrNull;
  }

  bool get _hasInvalidVisibleRow =>
      _rows.any((row) => _presetFor(row.presetId) == null);

  bool get _canSave =>
      _effectiveRows.isNotEmpty &&
      !_hasInvalidVisibleRow &&
      widget.generatorSetting != null;

  /// Rows surviving the native filter; the stored pool keeps everything.
  List<_PoolRow> get _effectiveRows {
    if (_teamMode != TeamMode.native) return _rows;
    return [
      for (final row in _rows)
        if (_presetFor(row.presetId)?.cli == _nativeCli) row,
    ];
  }

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
              // Generator model (AI feature row).
              Text(l10n.teamGenerateGeneratorModel, style: styles.mdSemibold),
              const SizedBox(height: 4),
              Text(
                widget.generatorSetting == null
                    ? l10n.teamGenerateErrorAiNotConfigured
                    : '${widget.generatorSetting!.cli.value} · '
                        '${widget.generatorSetting!.model}',
                style: styles.smMedium.copyWith(
                  color: widget.generatorSetting == null
                      ? cs.error
                      : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Team mode segmented selection.
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
                    if (_teamMode == TeamMode.native &&
                        _effectiveRows.isEmpty) {
                      // Default to the first valid stored pool preset's CLI.
                      final firstValid = _rows
                          .map((row) => _presetFor(row.presetId))
                          .whereType<CliPreset>()
                          .firstOrNull;
                      if (firstValid != null) _nativeCli = firstValid.cli;
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
                    for (final tool in CliToolRegistry.builtIn().launchable
                        .map((definition) => definition.id))
                      DropdownMenuItem(value: tool, child: Text(tool.value)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _nativeCli = value);
                  },
                ),
              ],
              const SizedBox(height: 16),

              // Ranked model pool.
              Text(l10n.teamGenerateModelPool, style: styles.mdSemibold),
              if (_teamMode == TeamMode.native && _hiddenCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.teamGenerateHiddenPresets(_hiddenCount),
                  style: styles.smMedium.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              for (var i = 0; i < _rows.length; i++)
                _poolRowTile(context, i),
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
    final preset = _presetFor(row.presetId);
    final invalid = preset == null;
    final hiddenInNative =
        _teamMode == TeamMode.native && preset != null && preset.cli != _nativeCli;

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
            color: invalid ? cs.error : cs.outlineVariant.withValues(alpha: 0.5),
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
                  child: Text(
                    invalid
                        ? l10n.teamGenerateMissingPreset(row.presetId)
                        : '${preset.name} · ${preset.cli.value} · '
                            '${preset.provider}/${preset.model}'
                            '${preset.effort.isEmpty ? '' : '/${preset.effort}'}',
                    style: styles.smMedium.copyWith(
                      color: invalid ? cs.error : null,
                    ),
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
                  icon: Icon(Icons.remove_circle_outline,
                      size: 18, color: cs.error),
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
                    onChanged: (value) => _rows[index] =
                        _PoolRow(presetId: row.presetId, description: value, tags: row.tags),
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
                    onChanged: (value) => _rows[index] = _PoolRow(
                      presetId: row.presetId,
                      description: row.description,
                      tags: [
                        for (final tag in value.split(','))
                          if (tag.trim().isNotEmpty) tag.trim(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (hiddenInNative)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.teamGenerateHiddenPresets(1),
                  style: styles.smMedium.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addModel() async {
    final l10n = context.l10n;
    final candidates = _visiblePresets
        .where((preset) => !_rows.any((row) => row.presetId == preset.id))
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(l10n.teamGenerateErrorPoolEmpty)),
      );
      return;
    }
    final selected = await showDialog<CliPreset>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.teamGenerateAddModel),
        children: [
          for (final preset in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(preset),
              child: Text(
                '${preset.name} · ${preset.cli.value} · '
                '${preset.provider}/${preset.model}',
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    setState(() {
      _rows.add(_PoolRow(presetId: selected.id));
    });
  }

  Future<void> _save(BuildContext context) async {
    final settings = TeamGenerationSettings(
      teamMode: _teamMode,
      nativeCli: _nativeCli,
      modelPool: [
        for (final row in _rows)
          GenerateModelPoolEntry(
            presetId: row.presetId,
            description: row.description,
            tags: row.tags,
          ),
      ],
    );
    await _store.save(settings);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _PoolRow {
  _PoolRow({
    required this.presetId,
    this.description = '',
    this.tags = const [],
  });

  final String presetId;
  final String description;
  final List<String> tags;
}
