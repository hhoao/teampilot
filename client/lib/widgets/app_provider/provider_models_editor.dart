import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../services/cli/registry/capabilities/provider_model_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../app_dialog.dart';
import '../app_icon_button.dart';
import '../dropdown/app_dropdown_decoration.dart';
import '../dropdown/app_dropdown_with_custom_input.dart';

/// One model row stored under `provider.config['models']`.
@immutable
class ProviderModelEntry {
  const ProviderModelEntry({
    required this.id,
    required this.name,
    required this.model,
    required this.enabled,
    this.tier = ProviderModelTier.standard,
    this.raw = const {},
  });

  final String id;
  final String name;
  final String model;
  final bool enabled;

  /// Tier role for tier-aware CLIs (Claude). Ignored when the CLI is flat.
  final ProviderModelTier tier;

  /// Extra keys (e.g. flashskyai `provider`) preserved on round-trip.
  final Map<String, Object?> raw;

  ProviderModelEntry copyWith({
    String? name,
    String? model,
    bool? enabled,
    ProviderModelTier? tier,
  }) => ProviderModelEntry(
    id: id,
    name: name ?? this.name,
    model: model ?? this.model,
    enabled: enabled ?? this.enabled,
    tier: tier ?? this.tier,
    raw: raw,
  );

  Map<String, Object?> toJson() => {
    ...raw,
    'name': name,
    'model': model,
    'enabled': enabled,
    if (tier != ProviderModelTier.standard) 'role': tier.value,
  };
}

/// CLI-agnostic editor for a provider's model list (`config['models']`).
///
/// Selecting a row as default writes its [ProviderModelEntry.model] back as the
/// provider's `defaultModel`; the launch-time materializer consumes that field,
/// so no per-CLI wiring is needed here.
class ProviderModelsEditor extends StatelessWidget {
  const ProviderModelsEditor({
    required this.cli,
    required this.draftProvider,
    required this.models,
    required this.defaultModel,
    required this.onChanged,
    super.key,
  });

  final CliTool cli;
  final AppProviderConfig Function() draftProvider;
  final Map<String, Object?>? models;
  final String defaultModel;
  final void Function(Map<String, Object?> models, String defaultModel)
  onChanged;

  static List<ProviderModelEntry> parse(Map<String, Object?>? models) {
    if (models == null) return const [];
    final out = <ProviderModelEntry>[];
    for (final entry in models.entries) {
      final value = entry.value;
      if (value is Map) {
        final map = Map<String, Object?>.from(value);
        out.add(
          ProviderModelEntry(
            id: entry.key,
            name: (map['name'] as String?)?.trim() ?? entry.key,
            model: (map['model'] as String?)?.trim() ?? entry.key,
            enabled: map['enabled'] as bool? ?? true,
            tier: ProviderModelTier.fromJson(map['role']),
            raw: map
              ..remove('name')
              ..remove('model')
              ..remove('enabled')
              ..remove('role'),
          ),
        );
      } else {
        out.add(
          ProviderModelEntry(
            id: entry.key,
            name: entry.key,
            model: entry.key,
            enabled: true,
          ),
        );
      }
    }
    return out;
  }

  static Map<String, Object?> _serialize(List<ProviderModelEntry> entries) => {
    for (final entry in entries) entry.id: entry.toJson(),
  };

  List<String> _suggestions(BuildContext context) {
    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
    final capability = registry.capability<ProviderModelCapability>(cli);
    if (capability == null) return const [];
    final draft = draftProvider();
    return capability.modelCandidates(
      provider: draft,
      providerId: draft.id,
      currentModel: '',
    );
  }

  bool _supportsTiers(BuildContext context) {
    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
    return registry
            .capability<ProviderModelCapability>(cli)
            ?.supportsModelTiers ??
        false;
  }

  void _commit(List<ProviderModelEntry> entries, {String? nextDefault}) {
    onChanged(_serialize(entries), nextDefault ?? defaultModel);
  }

  Future<void> _addOrEdit(
    BuildContext context, {
    ProviderModelEntry? existing,
  }) async {
    final l10n = context.l10n;
    final entries = parse(models);
    final result = await showDialog<ProviderModelEntry>(
      context: context,
      builder: (_) => _ProviderModelEntryDialog(
        title: existing == null
            ? l10n.addModel
            : l10n.editModelTitle(existing.name),
        existing: existing,
        suggestions: _suggestions(context),
      ),
    );
    if (result == null) return;

    final next = [...entries];
    final index = existing == null
        ? -1
        : next.indexWhere((e) => e.id == existing.id);
    if (index >= 0) {
      next[index] = result;
    } else if (next.any((e) => e.id == result.id)) {
      next[next.indexWhere((e) => e.id == result.id)] = result;
    } else {
      next.add(result);
    }
    final defaultEmpty = defaultModel.trim().isEmpty;
    _commit(next, nextDefault: defaultEmpty ? result.model : defaultModel);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final entries = parse(models);
    final supportsTiers = _supportsTiers(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.models, style: theme.textTheme.labelLarge),
            ),
            AppIconButton(
              icon: Icons.add,
              compact: true,
              size: AppIconButton.kCompactSize,
              tooltip: l10n.addModel,
              onTap: () => _addOrEdit(context),
            ),
          ],
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.noModelsConfigured,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final entry in entries)
            _ModelRow(
              entry: entry,
              isDefault: entry.model.trim() == defaultModel.trim() &&
                  defaultModel.trim().isNotEmpty,
              showTierToggle: supportsTiers,
              onSetDefault: () => _commit(entries, nextDefault: entry.model),
              onToggleEnabled: (value) {
                final next = entries
                    .map(
                      (e) =>
                          e.id == entry.id ? e.copyWith(enabled: value) : e,
                    )
                    .toList();
                _commit(next);
              },
              onToggleBackground: () {
                final makeBackground =
                    entry.tier != ProviderModelTier.background;
                // At most one background model; toggling one clears the rest.
                final next = entries
                    .map(
                      (e) => e.id == entry.id
                          ? e.copyWith(
                              tier: makeBackground
                                  ? ProviderModelTier.background
                                  : ProviderModelTier.standard,
                            )
                          : e.copyWith(tier: ProviderModelTier.standard),
                    )
                    .toList();
                _commit(next);
              },
              onEdit: () => _addOrEdit(context, existing: entry),
              onDelete: () {
                final next = entries.where((e) => e.id != entry.id).toList();
                final clearsDefault = entry.model.trim() == defaultModel.trim();
                _commit(next, nextDefault: clearsDefault ? '' : defaultModel);
              },
            ),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.entry,
    required this.isDefault,
    required this.showTierToggle,
    required this.onSetDefault,
    required this.onToggleEnabled,
    required this.onToggleBackground,
    required this.onEdit,
    required this.onDelete,
  });

  final ProviderModelEntry entry;
  final bool isDefault;
  final bool showTierToggle;
  final VoidCallback onSetDefault;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onToggleBackground;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final isBackground = entry.tier == ProviderModelTier.background;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.defaultModel,
            isSelected: isDefault,
            onPressed: onSetDefault,
            icon: Icon(
              isDefault ? Icons.star : Icons.star_border,
              size: 18,
              color: isDefault ? theme.colorScheme.primary : muted,
            ),
          ),
          if (showTierToggle)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l10n.providerModelBackgroundTier,
              isSelected: isBackground,
              onPressed: onToggleBackground,
              icon: Icon(
                isBackground ? Icons.bolt : Icons.bolt_outlined,
                size: 18,
                color: isBackground ? theme.colorScheme.tertiary : muted,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (entry.model.isNotEmpty && entry.model != entry.name)
                  Text(
                    entry.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 48,
            child: Switch(
              value: entry.enabled,
              onChanged: onToggleEnabled,
            ),
          ),
          AppIconButton(
            icon: Icons.edit_outlined,
            compact: true,
            size: AppIconButton.kCompactSize,
            tooltip: l10n.edit,
            onTap: onEdit,
          ),
          AppIconButton(
            icon: Icons.delete_outline,
            compact: true,
            size: AppIconButton.kCompactSize,
            tooltip: l10n.delete,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _ProviderModelEntryDialog extends StatefulWidget {
  const _ProviderModelEntryDialog({
    required this.title,
    required this.existing,
    required this.suggestions,
  });

  final String title;
  final ProviderModelEntry? existing;
  final List<String> suggestions;

  @override
  State<_ProviderModelEntryDialog> createState() =>
      _ProviderModelEntryDialogState();
}

class _ProviderModelEntryDialogState extends State<_ProviderModelEntryDialog> {
  late final TextEditingController _nameController;
  late String _model;
  late bool _enabled;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _model = widget.existing?.model ?? '';
    _enabled = widget.existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final deco = AppDropdownDecorations.themed(context, borderRadius: 8);
    return AppDialog(
      maxWidth: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: widget.title),
          const SizedBox(height: 16),
          Text(l10n.modelId, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          AppDropdownWithCustomInput(
            value: _model,
            items: widget.suggestions,
            hintText: l10n.selectModel,
            decoration: deco,
            onChanged: (value) => setState(() => _model = value),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: l10n.modelName),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.enabled),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: _save,
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _save() {
    final model = _model.trim();
    if (model.isEmpty) return;
    final name = _nameController.text.trim();
    Navigator.pop(
      context,
      ProviderModelEntry(
        id: _isEditing ? widget.existing!.id : model,
        name: name.isEmpty ? model : name,
        model: model,
        enabled: _enabled,
        raw: widget.existing?.raw ?? const {},
      ),
    );
  }
}
