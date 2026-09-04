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
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/team_generation/team_generation_settings_store.dart';
import '../../../widgets/cli_launch_config/launch_four_tuple_picker.dart';
import '../../../widgets/compose/compose_model_preset_chip.dart';

const double _kDialogWidth = 640;
const double _kDialogMaxHeight = 720;

/// Global generation settings: generator model (any launchable CLI), team mode,
/// native CLI (native mode only), and the ranked model pool.
///
/// Only the **model pool** is filtered by native CLI in native mode. The
/// generator builds the plan and stays independent of [TeamMode.native].
Future<void> showWorkspaceLandingGenerateSettingsDialog(
  BuildContext context, {
  required List<CliPreset> presets,
  required AiFeatureSetting? generatorSetting,
}) {
  return showTpDialog<void>(
    context: context,
    maxWidth: _kDialogWidth,
    maxHeight: _kDialogMaxHeight,
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
  SimpleLaunchFourTuple? _generator;
  var _loading = true;
  var _generatorInitialized = false;

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
      _loading = false;
    });
  }

  CliToolRegistry get _registry =>
      CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();

  List<CliTool> get _launchableCliItems => [
    for (final definition in _registry.launchable) definition.id,
  ];

  List<CliTool> get _nativeCliItems {
    final items = [
      for (final definition in _registry.nativeTeamLaunchable) definition.id,
    ]..sort((a, b) => a.value.compareTo(b.value));
    return items;
  }

  /// Pool pickers only — native mode locks to [\_nativeCli].
  List<CliTool> get _poolCliItems =>
      _teamMode == TeamMode.native ? [_nativeCli] : _launchableCliItems;

  bool _isVisibleRow(_PoolRow row) =>
      _teamMode != TeamMode.native || row.cli == _nativeCli;

  bool _isConfiguredRow(_PoolRow row) =>
      row.id.trim().isNotEmpty &&
      row.provider.trim().isNotEmpty &&
      row.model.trim().isNotEmpty;

  List<int> get _visibleIndices => [
    for (var i = 0; i < _rows.length; i++)
      if (_isVisibleRow(_rows[i])) i,
  ];

  int get _hiddenCount {
    if (_teamMode != TeamMode.native) return 0;
    return _rows.length - _visibleIndices.length;
  }

  AiFeatureSetting? get _draftGeneratorSetting {
    final generator = _generator;
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
    if (_loading) return false;
    return _effectiveRows.isNotEmpty &&
        aiFeatureIsConfigured(
          stored: _draftGeneratorSetting,
          registry: _registry,
          appProviders: context.read<AppProviderCubit>().state,
          globalPresets: widget.presets,
        );
  }

  List<_PoolRow> get _effectiveRows =>
      _rows.where(_isVisibleRow).where(_isConfiguredRow).toList();

  void _setTeamMode(TeamMode mode) {
    setState(() {
      _teamMode = mode;
      if (_teamMode != TeamMode.native) return;
      final nativeClis = _nativeCliItems;
      final firstMatching = _rows
          .where((row) => nativeClis.contains(row.cli))
          .firstOrNull;
      if (firstMatching != null) {
        _nativeCli = firstMatching.cli;
      } else if (!nativeClis.contains(_nativeCli)) {
        _nativeCli = nativeClis.firstOrNull ?? CliTool.claude;
      }
    });
  }

  void _moveVisible(int visiblePos, int delta) {
    final indices = _visibleIndices;
    final nextPos = visiblePos + delta;
    if (nextPos < 0 || nextPos >= indices.length) return;
    final a = indices[visiblePos];
    final b = indices[nextPos];
    setState(() {
      final tmp = _rows[a];
      _rows[a] = _rows[b];
      _rows[b] = tmp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final registry = _registry;

    return TpDialog(
      maxWidth: _kDialogWidth,
      maxHeight: _kDialogMaxHeight,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(title: l10n.teamGenerateSettingsTitle),
        body: _loading
            ? Padding(
                padding: EdgeInsets.symmetric(vertical: spacing.xl),
                child: Text(
                  l10n.teamGenerateLoading,
                  style: styles.smMedium.copyWith(color: cs.onSurfaceVariant),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.teamGenerateSettingsSubtitle,
                    style: styles.sm.copyWith(color: cs.onSurfaceVariant),
                  ),
                  SizedBox(height: spacing.lg),
                  _SectionLabel(l10n.teamGenerateGeneratorModel),
                  SizedBox(height: spacing.sm),
                  LaunchFourTuplePicker(
                    value: _generator,
                    cliItems: _launchableCliItems,
                    presets: widget.presets,
                    onChanged: (value) => setState(() => _generator = value),
                    showManagePresets: true,
                    showSavePreset: false,
                    emptyLabel: l10n.teamGenerateErrorAiNotConfigured,
                  ),
                  SizedBox(height: spacing.xl),
                  _SectionLabel(l10n.teamGenerateTeamMode),
                  SizedBox(height: spacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _ModeOption(
                          title: l10n.teamModeNativeTitle,
                          description: l10n.teamModeNativeDescription,
                          selected: _teamMode == TeamMode.native,
                          onTap: () => _setTeamMode(TeamMode.native),
                        ),
                      ),
                      SizedBox(width: spacing.sm),
                      Expanded(
                        child: _ModeOption(
                          title: l10n.teamModeMixedTitle,
                          description: l10n.teamModeMixedDescription,
                          selected: _teamMode == TeamMode.mixed,
                          onTap: () => _setTeamMode(TeamMode.mixed),
                        ),
                      ),
                    ],
                  ),
                  if (_teamMode == TeamMode.native) ...[
                    SizedBox(height: spacing.md),
                    _SectionLabel(l10n.teamGenerateNativeCli),
                    SizedBox(height: spacing.sm),
                    TpSelect<CliTool>(
                      key: ValueKey(
                        'native-cli-${_nativeCliItems.map((c) => c.value).join(',')}',
                      ),
                      items: _nativeCliItems,
                      initialItem: _nativeCliItems.contains(_nativeCli)
                          ? _nativeCli
                          : _nativeCliItems.firstOrNull,
                      searchable: false,
                      itemLabel: (tool) {
                        final definition = registry.tryGet(tool);
                        return definition == null
                            ? tool.value
                            : cliDisplayName(definition, l10n);
                      },
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _nativeCli = value);
                      },
                    ),
                  ],
                  SizedBox(height: spacing.xl),
                  _SectionLabel(l10n.teamGenerateModelPool),
                  SizedBox(height: spacing.xs),
                  Text(
                    l10n.teamGenerateModelPoolHint,
                    style: styles.sm.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (_hiddenCount > 0) ...[
                    SizedBox(height: spacing.xs),
                    Text(
                      l10n.teamGenerateHiddenPresets(_hiddenCount),
                      style: styles.sm.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                  SizedBox(height: spacing.md),
                  if (_visibleIndices.isEmpty)
                    _EmptyPoolHint(text: l10n.teamGenerateEmptyPool)
                  else
                    for (var visiblePos = 0;
                        visiblePos < _visibleIndices.length;
                        visiblePos++)
                      Padding(
                        padding: EdgeInsets.only(bottom: spacing.sm),
                        child: _poolRowTile(
                          context,
                          visiblePos: visiblePos,
                          rowIndex: _visibleIndices[visiblePos],
                        ),
                      ),
                  SizedBox(height: spacing.sm),
                  TpButton(
                    variant: TpButtonVariant.outline,
                    onPressed: _addModel,
                    child: Text(l10n.teamGenerateAddModel),
                  ),
                  SizedBox(height: spacing.lg),
                  Text(
                    l10n.teamGenerateCapabilityNote,
                    style: styles.sm.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
        footer: TpDialogActions(
          children: [
            TpButton(
              variant: TpButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            TpButton(
              onPressed: _canSave ? () => _save(context) : null,
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  Widget _poolRowTile(
    BuildContext context, {
    required int visiblePos,
    required int rowIndex,
  }) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final row = _rows[rowIndex];
    final indices = _visibleIndices;
    final configured = _isConfiguredRow(row);

    return TpCard.outlined(
      key: ValueKey('pool-row-${row.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${visiblePos + 1}.', style: styles.mdSemibold),
              SizedBox(width: spacing.sm),
              Expanded(
                child: LaunchFourTuplePicker(
                  value: configured
                      ? SimpleLaunchFourTuple(
                          cli: row.cli,
                          providerId: row.provider,
                          modelId: row.model,
                          effort: row.effort,
                        )
                      : null,
                  cliItems: _poolCliItems,
                  presets: widget.presets,
                  onChanged: (value) => setState(() {
                    row.cli = value.cli;
                    row.provider = value.providerId;
                    row.model = value.modelId;
                    row.effort = value.effort;
                  }),
                  showManagePresets: true,
                  showSavePreset: false,
                  emptyLabel: l10n.teamGeneratePickPreset,
                ),
              ),
              IconButton(
                tooltip: l10n.teamGenerateMoveUp,
                onPressed: visiblePos > 0
                    ? () => _moveVisible(visiblePos, -1)
                    : null,
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                tooltip: l10n.teamGenerateMoveDown,
                onPressed: visiblePos < indices.length - 1
                    ? () => _moveVisible(visiblePos, 1)
                    : null,
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
              IconButton(
                tooltip: l10n.teamGenerateRemove,
                onPressed: () => setState(() => _rows.removeAt(rowIndex)),
                icon: Icon(Icons.close, size: 18, color: cs.error),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('pool-desc-${row.id}'),
                  initialValue: row.description,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l10n.teamGenerateDescription,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) => row.description = value,
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: TextFormField(
                  key: ValueKey('pool-tags-${row.id}'),
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
    );
  }

  Future<void> _addModel() async {
    SimpleLaunchFourTuple? selected;
    await showTpDialog<void>(
      context: context,
      maxWidth: 420,
      builder: (dialogContext) => TpDialog(
        maxWidth: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: context.l10n.teamGenerateAddModel),
            const SizedBox(height: 12),
            LaunchFourTuplePicker(
              value: null,
              cliItems: _poolCliItems,
              presets: widget.presets,
              onChanged: (value) {
                selected = value;
                Navigator.of(dialogContext).pop();
              },
              showManagePresets: true,
              showSavePreset: false,
              emptyLabel: context.l10n.teamGenerateAddModel,
            ),
            TpDialogActions(
              children: [
                TpButton(
                  variant: TpButtonVariant.ghost,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(context.l10n.cancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final value = selected;
    if (value == null || !mounted) return;
    setState(() {
      _rows.add(
        _PoolRow(
          id: const Uuid().v4(),
          cli: value.cli,
          provider: value.providerId,
          model: value.modelId,
          effort: value.effort,
        ),
      );
    });
  }

  Future<void> _save(BuildContext context) async {
    final generator = _generator;
    if (generator == null) return;
    if (!aiFeatureIsConfigured(
      stored: _draftGeneratorSetting,
      registry: _registry,
      appProviders: context.read<AppProviderCubit>().state,
      globalPresets: widget.presets,
    )) {
      return;
    }
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TpTextStyles.of(context).mdSemibold);
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final radius = BorderRadius.circular(12);
    return TpHover(
      onTap: onTap,
      borderRadius: radius,
      backgroundColor: selected
          ? cs.primary.withValues(alpha: 0.08)
          : cs.surfaceContainerHighest.withValues(alpha: 0.4),
      hoverColor: selected
          ? cs.primary.withValues(alpha: 0.1)
          : cs.surfaceContainerHighest.withValues(alpha: 0.55),
      border: Border.all(
        color: selected
            ? cs.primary
            : cs.outlineVariant.withValues(alpha: 0.55),
        width: selected ? 2 : 1,
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.mdSemibold.copyWith(
              color: selected ? cs.primary : cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: styles.sm.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPoolHint extends StatelessWidget {
  const _EmptyPoolHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.tpSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.tpTheme.control.radius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Text(
        text,
        style: TpTextStyles.of(
          context,
        ).sm.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}
