import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/run/launch_configuration.dart';
import '../../models/workspace_folder.dart';
import '../../services/run/shell_script_launch_schema.dart';
import 'package:shared_ui/shared_ui.dart';
import '../menu/sidebar_action_menu.dart';
import 'run_config_editor_dialog.dart';

/// Workspace-scoped launch configurations list in a modal dialog
/// (automation-panel style: list everything; Add opens a second dialog).
class RunConfigurationsDialog extends StatelessWidget {
  const RunConfigurationsDialog({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return TpDialog(
      maxWidth: 720,
      maxHeight: maxHeight,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(
          title: l10n.runConfigureLaunchItems,
          trailing: TpIconButton(
            key: const Key('run-configurations-add'),
            icon: Icons.add_rounded,
            tooltip: l10n.runAddConfiguration,
            onTap: () => unawaited(_create(context)),
          ),
        ),
        bodyTopSpacing: 8,
        body: _RunConfigurationsListBody(workspaceId: workspaceId),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    await createRunConfiguration(
      context,
      workspaceId: workspaceId,
    );
  }
}

/// Opens the add-configuration editor (defaults to Shell Script; type is a
/// dropdown inside the editor). Shared by list dialog and toolbar.
Future<void> createRunConfiguration(
  BuildContext context, {
  required String workspaceId,
  WorkspaceFolder? folder,
}) {
  return showRunConfigEditorDialog(
    context,
    workspaceId: workspaceId,
    createNew: true,
    initialType: ShellScriptLaunchSchema.typeName,
    folder: folder,
  );
}

/// Opens [RunConfigurationsDialog] from the Run toolbar config menu.
Future<void> showRunConfigurationsPanelDialog(
  BuildContext context, {
  required String workspaceId,
}) {
  final cubit = context.read<RunCubit>();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => BlocProvider<RunCubit>.value(
      value: cubit,
      child: RunConfigurationsDialog(workspaceId: workspaceId),
    ),
  );
}

class _RunConfigurationsListBody extends StatelessWidget {
  const _RunConfigurationsListBody({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);

    return BlocBuilder<RunCubit, RunState>(
      builder: (context, state) {
        final configs = state.configurations;
        if (configs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.runConfigurationsEmpty,
              style: styles.mdColored(cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          );
        }

        final multiFolder = context.read<RunCubit>().folders.length > 1;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          itemCount: configs.length,
          itemBuilder: (context, index) {
            final owned = configs[index];
            return _RunConfigurationRow(
              owned: owned,
              subtitle: multiFolder ? _folderLabel(owned.owner) : null,
              workspaceId: workspaceId,
            );
          },
        );
      },
    );
  }
}

class _RunConfigurationRow extends StatelessWidget {
  const _RunConfigurationRow({
    required this.owned,
    required this.workspaceId,
    this.subtitle,
  });

  final OwnedLaunchConfiguration owned;
  final String workspaceId;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final title = owned.configuration.name.isEmpty
        ? owned.configId
        : owned.configuration.name;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Icon(
              Icons.play_arrow_outlined,
              size: context.tpIconSizes.md,
              color: cs.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.lg,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    owned.configuration.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.xsColored(cs.onSurfaceVariant),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.xsMediumColored(cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            SidebarActionMenuIconAnchor(
              key: Key('run-config-row-menu-${owned.selectionKey}'),
              icon: Icon(Icons.more_vert, size: context.tpIconSizes.md),
              buildMenuChildren: (ctx, controller) => [
                SidebarActionMenuItem(
                  icon: Icons.edit_outlined,
                  label: l10n.edit,
                  menuController: controller,
                  onTap: () => unawaited(_edit(context)),
                ),
                SidebarActionMenuItem(
                  icon: Icons.delete_outline,
                  label: l10n.runDeleteConfiguration,
                  destructive: true,
                  menuController: controller,
                  onTap: () => unawaited(_delete(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    await showRunConfigEditorDialog(
      context,
      workspaceId: workspaceId,
      initial: owned,
    );
  }

  Future<void> _delete(BuildContext context) async {
    final cubit = context.read<RunCubit>();
    final l10n = context.l10n;
    final running = cubit.hasRunning(owned.selectionKey);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return TpDialog(
          maxWidth: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpDialogHeader(
                title: l10n.runDeleteConfiguration,
                onClose: () => Navigator.of(ctx).pop(false),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.runDeleteConfigurationConfirm(
                  owned.configuration.name.isEmpty
                      ? owned.configId
                      : owned.configuration.name,
                ),
              ),
              TpDialogActions(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(
                      running
                          ? l10n.runStopAndDelete
                          : l10n.runDeleteConfiguration,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    await cubit.deleteConfiguration(owned);
  }
}

String _folderLabel(WorkspaceFolder folder) {
  final path = folder.path.replaceAll('\\', '/');
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return path.isEmpty ? folder.path : path;
  return parts.last;
}
