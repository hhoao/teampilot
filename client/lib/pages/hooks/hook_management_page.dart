import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/hook_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/hook_definition.dart';
import '../../services/hook/hook_repository.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/settings/workspace_section_host.dart';
import '../../widgets/settings/workspace_section_nav_item.dart';
import 'hook_editor_dialog.dart';

class HookManagementPage extends StatelessWidget {
  const HookManagementPage({super.key});

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
      onBack: () => context.go('/home-v2'),
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TpButton(
                  onPressed: () => _openEditor(
                    context,
                    cubit: context.read<HookCubit>(),
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
              ),
              const SizedBox(height: 12),
              if (definitions.isEmpty)
                TpEmptyState(
                  icon: Icons.bolt_outlined,
                  title: l10n.hooksNoInstalled,
                  hint: l10n.hooksNoInstalledHint,
                )
              else
                for (final definition in definitions)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.bolt_outlined),
                      title: Text(
                        definition.name.isEmpty
                            ? definition.id
                            : definition.name,
                      ),
                      subtitle: Text(
                        '${definition.event.name}'
                        '${definition.matcher == null ? '' : ' · ${definition.matcher}'}',
                      ),
                      onTap: () => _openEditor(
                        context,
                        cubit: context.read<HookCubit>(),
                        definition: definition,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await context
                              .read<HookCubit>()
                              .remove(definition.id);
                        },
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
