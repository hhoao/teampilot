import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/llm_config_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/llm_config.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/app_icon_button.dart';
import 'llm_config_routes.dart';
import 'llm_model_edit_dialog.dart';
import 'llm_workspace_typography.dart';

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
