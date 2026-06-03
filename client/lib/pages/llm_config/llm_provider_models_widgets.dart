import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/llm_config_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/llm_config.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import 'llm_config_routes.dart';
import 'llm_workspace_typography.dart';

// --- Provider models mini table ---

class LlmProviderModelsTable extends StatelessWidget {
  const LlmProviderModelsTable({
    required this.models,
    required this.providers,
    required this.onUpdate,
    required this.onDelete,
    super.key,
  });

  final List<LlmModelConfig> models;
  final Map<String, LlmProviderConfig> providers;
  final void Function(String, LlmModelConfig) onUpdate;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = LlmWorkspaceText(theme);
    final l10n = context.l10n;
    final isDark = theme.brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final model in models)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tx.bodyStrongColored(textBase),
                      ),
                      if (model.model.isNotEmpty &&
                          model.model != model.name) ...[
                        const SizedBox(height: 2),
                        Text(
                          model.model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx.smallColored(muted),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Switch(
                    key: AppKeys.modelEnabledToggle,
                    value: model.enabled,
                    onChanged: (value) {
                      onUpdate(model.id, model.copyWith(enabled: value));
                    },
                  ),
                ),
                AppIconButton(
                  icon: Icons.edit_outlined,
                  iconSize: AppIconButton.kCompactIconSize,
                  size: AppIconButton.kCompactSize,
                  tooltip: l10n.edit,
                  onTap: () => _editModel(context, model),
                ),
                AppIconButton(
                  icon: Icons.delete_outline,
                  iconSize: AppIconButton.kCompactIconSize,
                  size: AppIconButton.kCompactSize,
                  tooltip: l10n.delete,
                  onTap: () => onDelete(model.id),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _editModel(BuildContext context, LlmModelConfig model) async {
    final l10n = context.l10n;
    final result = await showDialog<LlmModelConfig>(
      context: context,
      builder: (context) => LlmModelEditDialog(
        model: model,
        providers: providers,
        title: l10n.editModelTitle(model.name),
      ),
    );
    if (result != null) {
      onUpdate(model.id, result);
    }
  }
}

// --- App provider models (FlashskyAI) ---

class LlmAppProviderModelsPanel extends StatelessWidget {
  const LlmAppProviderModelsPanel({
    super.key,
    required this.provider,
    required this.onBack,
  });

  final AppProviderConfig provider;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final appCubit = context.watch<AppProviderCubit>();
    final config = appCubit.flashskyaiLlmConfigFor(provider);
    final llmProvider = config.providers[provider.id];
    if (llmProvider == null) {
      return Center(
        child: Text('${context.l10n.missingProvider} ${provider.id}'),
      );
    }

    Future<void> persist(Map<String, LlmModelConfig> models) {
      return appCubit.updateFlashskyaiModels(provider.id, models);
    }

    return LlmProviderModelsView(
      key: ValueKey('app-models-${provider.id}-${config.models.length}'),
      config: config,
      provider: llmProvider,
      onPersistModels: persist,
      onBack: onBack,
    );
  }
}

// --- Provider models view ---

class LlmProviderModelsView extends StatelessWidget {
  const LlmProviderModelsView({
    required this.config,
    required this.provider,
    this.controller,
    this.onPersistModels,
    required this.onBack,
    super.key,
  }) : assert(
         controller != null || onPersistModels != null,
         'Provide controller or onPersistModels',
       );

  final LlmConfig config;
  final LlmProviderConfig provider;
  final LlmConfigCubit? controller;
  final Future<void> Function(Map<String, LlmModelConfig> models)?
  onPersistModels;
  final VoidCallback onBack;

  Future<void> _saveAll(
    BuildContext context,
    Map<String, LlmModelConfig> models,
  ) async {
    if (onPersistModels != null) {
      await onPersistModels!(models);
      return;
    }
    final c = controller!;
    for (final entry in models.entries) {
      if (config.models.containsKey(entry.key)) {
        c.updateModel(entry.key, entry.value);
      } else {
        c.addModel(entry.value);
      }
    }
    for (final id in config.models.keys) {
      if (!models.containsKey(id)) {
        c.deleteModel(id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tx = LlmWorkspaceText(theme);
    final l10n = context.l10n;
    final isDark = theme.brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final providerModels = config.models.values
        .where((m) => m.provider == provider.name)
        .toList();

    return Container(
      decoration: workspaceCardDecoration(cs),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                AppIconButton(
                  icon: Icons.arrow_back,
                  size: 40,
                  tooltip: l10n.back,
                  onTap: onBack,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l10n.models} — ${provider.name}',
                        style: tx.panelHeaderColored(textBase),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _addModel(context, provider.name),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        '+ ${l10n.add}',
                        style: tx.smallColored(
                          cs.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: providerModels.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(kLlmInsetH),
                      child: Text(l10n.noModelsConfigured, style: tx.mutedBody),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemCount: providerModels.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final model = providerModels[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: textBase.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    model.name,
                                    style: tx.bodyStrongColored(textBase),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    model.model,
                                    style: tx.smallColored(
                                      textBase.withValues(alpha: 0.54),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: model.enabled,
                              onChanged: (value) async {
                                final next = Map<String, LlmModelConfig>.from(
                                  config.models,
                                );
                                next[model.id] = model.copyWith(enabled: value);
                                await _saveAll(context, next);
                              },
                            ),
                            AppIconButton(
                              icon: Icons.edit_outlined,
                              iconSize: AppIconButton.kCompactIconSize,
                              size: 36,
                              tooltip: l10n.edit,
                              onTap: () => _editModel(context, model),
                            ),
                            AppIconButton(
                              icon: Icons.delete_outline,
                              iconSize: AppIconButton.kCompactIconSize,
                              size: 36,
                              tooltip: l10n.delete,
                              onTap: () async {
                                final next = Map<String, LlmModelConfig>.from(
                                  config.models,
                                )..remove(model.id);
                                await _saveAll(context, next);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addModel(BuildContext context, String providerName) async {
    final l10n = context.l10n;
    final result = await showDialog<LlmModelConfig>(
      context: context,
      builder: (context) => LlmModelEditDialog(
        providers: config.providers,
        defaultProvider: providerName,
        title: l10n.addModel,
      ),
    );
    if (result != null) {
      if (!context.mounted) return;
      final next = Map<String, LlmModelConfig>.from(config.models);
      next[result.id] = result;
      await _saveAll(context, next);
    }
  }

  Future<void> _editModel(BuildContext context, LlmModelConfig model) async {
    final l10n = context.l10n;
    final result = await showDialog<LlmModelConfig>(
      context: context,
      builder: (context) => LlmModelEditDialog(
        model: model,
        providers: config.providers,
        title: l10n.editModelTitle(model.name),
      ),
    );
    if (result != null) {
      if (!context.mounted) return;
      final next = Map<String, LlmModelConfig>.from(config.models);
      next[model.id] = result;
      await _saveAll(context, next);
    }
  }
}

// --- Validation dialog ---

// ignore: unused_element
Future<void> _showValidationDialog(BuildContext context, LlmConfig config) {
  final l10n = context.l10n;
  final messages = config.validationMessages;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.validation),
      content: SizedBox(
        width: 400,
        child: messages.isEmpty
            ? Text(l10n.allChecksPassed)
            : ListView.separated(
                shrinkWrap: true,
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final body = Theme.of(context).textTheme.bodyMedium;
                  return Text(
                    '${index + 1}. ${messages[index]}',
                    style: (body ?? const TextStyle()).copyWith(height: 1.35),
                  );
                },
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}

// --- Model edit dialog ---

class LlmModelEditDialog extends StatefulWidget {
  const LlmModelEditDialog({
    super.key,
    required this.providers,
    this.model,
    this.defaultProvider = '',
    required this.title,
  });

  final Map<String, LlmProviderConfig> providers;
  final LlmModelConfig? model;
  final String defaultProvider;
  final String title;

  @override
  State<LlmModelEditDialog> createState() => LlmModelEditDialogState();
}

class LlmModelEditDialogState extends State<LlmModelEditDialog> {
  late final TextEditingController _nameController;
  late String _provider;
  late final TextEditingController _modelController;
  late bool _enabled;

  bool get isEditing => widget.model != null;

  @override
  void initState() {
    super.initState();
    final model = widget.model;
    _nameController = TextEditingController(text: model?.name ?? '');
    _provider = model?.provider ?? widget.defaultProvider;
    _modelController = TextEditingController(text: model?.model ?? '');
    _enabled = model?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final providerNames = widget.providers.keys.toList()..sort();
    final deco = AppDropdownDecorations.themed(
      context,
      borderRadius: 8,
      headerFontWeight: FontWeight.w500,
      suffixIconSize: AppIconSizes.md,
      expandedShadowBlurRadius: 18,
      expandedShadowAlphaDark: 0.45,
    );
    final initialProvider = widget.providers.containsKey(_provider)
        ? _provider
        : null;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: AppKeys.modelNameDialogField,
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.modelName),
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.provider,
                  style: LlmWorkspaceText(Theme.of(context)).bodyStrong,
                ),
                const SizedBox(height: 8),
                AppDropdownField<String>(
                  key: AppKeys.modelProviderField,
                  items: providerNames,
                  initialItem: initialProvider,
                  hintText: l10n.provider,
                  decoration: deco,
                  onChanged: (value) => setState(() => _provider = value ?? ''),
                  itemLabel: (value) => value,
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: AppKeys.modelModelIdField,
              controller: _modelController,
              decoration: InputDecoration(labelText: l10n.modelId),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              key: AppKeys.modelEnabledToggle,
              title: Text(l10n.enabled),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              LlmModelConfig(
                id: isEditing ? widget.model!.id : name,
                name: name,
                provider: _provider,
                model: _modelController.text.trim(),
                enabled: _enabled,
              ),
            );
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
