import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/hook_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/hook_definition.dart';
import '../../services/hook/hook_repository.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/settings/workspace_section_host.dart';
import '../../widgets/settings/workspace_section_nav_item.dart';
import '../../widgets/workspace_library_card.dart';
import 'hook_editor_dialog.dart';
import 'hook_import_dialog.dart';

class HookManagementPage extends StatelessWidget {
  const HookManagementPage({this.embedded = false, super.key});

  /// When true, skip the page inset — parent (home) already applied
  /// [WorkspacePaneInsets.page].
  final bool embedded;

  Future<void> _openEditor(
    BuildContext context, {
    required HookCubit cubit,
    HookDefinition? definition,
  }) {
    return showHookEditorDialog(
      context,
      cubit: cubit,
      definition: definition,
      repository: context.read<HookRepository>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WorkspaceAdaptiveSectionPage(
      pageKey: AppKeys.hooksWorkspace,
      title: l10n.hookNavTitle,
      embedded: embedded,
      compactSectionTabs: true,
      items: [
        WorkspaceSectionNavItem(
          label: l10n.hookNavTitle,
          icon: Icons.bolt_outlined,
          selected: true,
          onSelect: () {},
        ),
      ],
      body: BlocBuilder<HookCubit, HookLibraryState>(
        builder: (context, state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final definitions = state.definitions;
          final cubit = context.read<HookCubit>();
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WorkspaceLibraryCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TpCardHeader(
                        title: l10n.hookInstalledCount(definitions.length),
                        trailing: TpActionRow(
                          children: [
                            OutlinedButton.icon(
                              key: const Key('hook-import'),
                              onPressed: () async {
                                final imported =
                                    await showHookImportDialog(context);
                                if (imported == true && context.mounted) {
                                  AppToast.show(
                                    context,
                                    message: context.l10n.hookImportDoneToast,
                                    variant: TpToastVariant.success,
                                  );
                                }
                              },
                              icon: const Icon(Icons.file_download_outlined),
                              label: Text(l10n.hookImport),
                            ),
                            FilledButton(
                              onPressed: () => _openEditor(
                                context,
                                cubit: cubit,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add, size: context.tpIconSizes.md),
                                  const SizedBox(width: 6),
                                  Text(l10n.hookNew),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (definitions.isEmpty)
                        TpEmptyState(
                          icon: Icons.bolt_outlined,
                          title: l10n.hooksNoInstalled,
                          hint: l10n.hooksNoInstalledHint,
                        )
                      else
                        for (final definition in definitions)
                          _HookRow(
                            definition: definition,
                            onEdit: () => _openEditor(
                              context,
                              cubit: cubit,
                              definition: definition,
                            ),
                            onDelete: () => cubit.remove(definition.id),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HookRow extends StatelessWidget {
  const _HookRow({
    required this.definition,
    required this.onEdit,
    required this.onDelete,
  });

  final HookDefinition definition;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final title = definition.name.isEmpty ? definition.id : definition.name;
    final subtitle = definition.matcher == null
        ? definition.event.name
        : '${definition.event.name} · ${definition.matcher}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onEdit,
          child: Row(
            children: [
              Icon(
                Icons.bolt_outlined,
                size: context.tpIconSizes.md,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TpTextStyles.of(context).mdBold),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TpTextStyles.of(
                        context,
                      ).smColored(cs.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: l10n.hookEdit,
                visualDensity: VisualDensity.compact,
                iconSize: context.tpIconSizes.md,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: l10n.delete,
                visualDensity: VisualDensity.compact,
                iconSize: context.tpIconSizes.md,
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, color: cs.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
