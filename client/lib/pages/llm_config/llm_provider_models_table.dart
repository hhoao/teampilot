import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/llm_config.dart';
import '../../utils/app_keys.dart';
import '../../widgets/app_icon_button.dart';
import 'llm_model_edit_dialog.dart';
import 'llm_workspace_typography.dart';

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
