import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/cli_presets_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/cli_preset.dart';
import '../../../../models/team_config.dart';
import '../../../../services/cli/registry/cli_display_name.dart';
import '../../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../../widgets/app_dialog.dart';
import 'cli_preset_edit_dialog.dart';

class CliPresetsManageDialog extends StatelessWidget {
  const CliPresetsManageDialog({this.lockCli, super.key});

  /// When non-null, passed through to [CliPresetEditDialog] to lock the CLI
  /// dropdown. Used in native mode to restrict presets to the team CLI.
  final CliTool? lockCli;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<CliPresetsCubit>().state;
    final presets = state.presets;

    return AppDialog(
      maxWidth: 640,
      scrollable: true,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.workspaceCliPresetsManageTitle),
          const SizedBox(height: 16),
          if (presets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.workspaceCliPresetsEmptyHint,
                textAlign: TextAlign.center,
                style: AppTextStyles.of(context).body,
              ),
            )
          else
            ...presets.map((preset) => _PresetRow(preset: preset)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _openAddDialog(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.workspaceCliAddPresetTitle),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openAddDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => CliPresetEditDialog(lockCli: lockCli),
    );
  }

  void _openEditDialog(BuildContext context, CliPreset preset) {
    showDialog<void>(
      context: context,
      builder: (_) => CliPresetEditDialog(existing: preset, lockCli: lockCli),
    );
  }

  Future<void> _deletePreset(BuildContext context, CliPreset preset) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workspaceCliDeletePresetTitle),
        content: Text(l10n.workspaceCliDeletePresetConfirm(preset.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<CliPresetsCubit>().deletePreset(preset.id);
    }
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.preset});

  final CliPreset preset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final def = registry.tryGet(preset.cli);
    final cliName = def != null ? cliDisplayName(def, l10n) : preset.cli.value;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final subtitle = _subtitle(preset);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preset.name,
                  style: styles.prominent.copyWith(color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  '$cliName · $subtitle',
                  style: styles.bodySmall.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: l10n.edit,
            onPressed: () {
              final dialog = context
                  .findAncestorWidgetOfExactType<CliPresetsManageDialog>();
              if (dialog != null) {
                dialog._openEditDialog(context, preset);
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.delete_outlined, size: 20, color: cs.error),
            tooltip: l10n.delete,
            onPressed: () {
              final dialog = context
                  .findAncestorWidgetOfExactType<CliPresetsManageDialog>();
              if (dialog != null) {
                dialog._deletePreset(context, preset);
              }
            },
          ),
        ],
      ),
    );
  }

  String _subtitle(CliPreset preset) {
    final parts = <String>[];
    if (preset.provider.isNotEmpty) parts.add(preset.provider);
    if (preset.model.isNotEmpty) parts.add(preset.model);
    if (preset.effort.isNotEmpty) parts.add(preset.effort);
    return parts.isNotEmpty ? parts.join(' · ') : 'Not configured';
  }
}
