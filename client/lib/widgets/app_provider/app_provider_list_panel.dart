import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import '../dropdown/app_dropdown_field.dart';
import '../menu/sidebar_action_menu.dart';

class AppProviderListPanel extends StatefulWidget {
  const AppProviderListPanel({
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onImport,
    required this.onEdit,
    required this.onDelete,
    this.hubStyle = false,
    super.key,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final Future<void> Function() onImport;
  final ValueChanged<AppProviderConfig> onEdit;
  final ValueChanged<String> onDelete;
  final bool hubStyle;

  @override
  State<AppProviderListPanel> createState() => _AppProviderListPanelState();
}

class _AppProviderListPanelState extends State<AppProviderListPanel> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final appCubit = context.watch<AppProviderCubit>();
    final headerBg = widget.hubStyle ? cs.workspacePage : cs.workspaceCard;
    final providers = appCubit.state.providers
        .where(
          (p) =>
              _query.isEmpty ||
              p.name.toLowerCase().contains(_query.toLowerCase()) ||
              p.id.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList(growable: false);

    return Material(
      key: AppKeys.llmProviderList,
      color: widget.hubStyle ? Colors.transparent : cs.workspaceCard,
      shape: widget.hubStyle
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: cs.outlineVariant),
            ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: _ProviderListControls(
              search: _search,
              onQueryChanged: (value) => setState(() => _query = value),
              onAdd: widget.onAdd,
              onImport: widget.onImport,
              isLoading: appCubit.state.isLoading,
              selectedCli: appCubit.state.selectedCli,
              onCliChanged: appCubit.setSelectedCli,
            ),
          ),
          Expanded(
            child: providers.isEmpty
                ? Center(child: Text(l10n.selectProvider))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: providers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final p = providers[index];
                      return _ProviderListTile(
                        provider: p,
                        selected: !widget.hubStyle && p.id == widget.selectedId,
                        hubStyle: widget.hubStyle,
                        modelCount: appCubit
                            .flashskyaiLlmConfigFor(p)
                            .models
                            .length,
                        onTap: () => widget.onSelect(p.id),
                        onEdit: () => widget.onEdit(p),
                        onDelete: () => widget.onDelete(p.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProviderListControls extends StatelessWidget {
  const _ProviderListControls({
    required this.search,
    required this.onQueryChanged,
    required this.onAdd,
    required this.onImport,
    required this.isLoading,
    required this.selectedCli,
    required this.onCliChanged,
  });

  final TextEditingController search;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onAdd;
  final Future<void> Function() onImport;
  final bool isLoading;
  final CliTool selectedCli;
  final ValueChanged<CliTool> onCliChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  l10n.providerList,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              SidebarActionMenuButton(
                tooltip: l10n.add,
                icon: const Icon(Icons.add),
                size: 32,
                specs: [
                  SidebarActionMenuSpec.item(
                    value: 'add',
                    icon: Icons.add,
                    label: l10n.addProvider,
                  ),
                  SidebarActionMenuSpec.item(
                    value: 'import',
                    icon: Icons.upload_file_outlined,
                    label: l10n.appProviderImport,
                    enabled: !isLoading,
                  ),
                ],
                onSelected: (action) {
                  switch (action) {
                    case 'add':
                      onAdd();
                    case 'import':
                      onImport();
                  }
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: AppDropdownField<CliTool>(
            items: CliTool.values,
            initialItem: selectedCli,
            itemLabel: l10n.appProviderToolLabel,
            onChanged: (cli) {
              if (cli != null) onCliChanged(cli);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: TextField(
            controller: search,
            decoration: InputDecoration(
              hintText: l10n.filterProviders,
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
            onChanged: (v) => onQueryChanged(v.trim()),
          ),
        ),
      ],
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  const _ProviderListTile({
    required this.provider,
    required this.selected,
    required this.hubStyle,
    required this.modelCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final AppProviderConfig provider;
  final bool selected;
  final bool hubStyle;
  final int modelCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final subtitle = provider.cli == CliTool.flashskyai
        ? l10n.providerListModelCount(modelCount)
        : l10n.appProviderToolLabel(provider.cli);
    final titleColor = selected ? cs.onPrimaryContainer : cs.onSurface;
    final subtitleColor = selected
        ? cs.onPrimaryContainer.withValues(alpha: 0.74)
        : cs.onSurfaceVariant;
    final tileColor = selected
        ? cs.primaryContainer
        : hubStyle
        ? cs.workspaceSubtleSurface
        : cs.workspaceInset;

    return ListTile(
      dense: true,
      selected: selected,
      tileColor: tileColor,
      selectedTileColor: cs.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      iconColor: titleColor,
      textColor: titleColor,
      title: Text(
        provider.name,
        style: TextStyle(
          color: titleColor,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: subtitleColor),
      ),
      trailing: hubStyle
          ? Icon(Icons.chevron_right, color: titleColor)
          : SidebarActionMenuButton(
              icon: Icon(Icons.more_horiz, color: titleColor),
              specs: [
                SidebarActionMenuSpec.item(
                  value: 'edit',
                  icon: Icons.edit_outlined,
                  label: l10n.edit,
                ),
                SidebarActionMenuSpec.item(
                  value: 'delete',
                  icon: Icons.delete_outline,
                  label: l10n.delete,
                  destructive: true,
                ),
              ],
              onSelected: (action) {
                switch (action) {
                  case 'edit':
                    onEdit();
                  case 'delete':
                    onDelete();
                }
              },
            ),
      onTap: onTap,
      onLongPress: onEdit,
    );
  }
}
