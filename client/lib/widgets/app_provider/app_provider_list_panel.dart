import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import '../app_outline_text_field.dart';
import '../dropdown/flashsky_dropdown_field.dart';
import '../dropdown/flashskyai_dropdown_decoration.dart';

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
      clipBehavior: widget.hubStyle ? Clip.none : Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.providerList,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: appCubit.state.isLoading
                              ? null
                              : () => widget.onImport(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(l10n.appProviderImport),
                        ),
                        TextButton(
                          onPressed: widget.onAdd,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text('+ ${l10n.add}'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FlashskyDropdownField<AppProviderCli>(
                    items: AppProviderCli.values,
                    initialItem: appCubit.state.selectedCli,
                    decoration: FlashskyDropdownDecorations.denseField(context),
                    itemLabel: l10n.appProviderCliLabel,
                    onChanged: (cli) {
                      if (cli != null) appCubit.setSelectedCli(cli);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AppOutlineTextField(
              controller: _search,
              hintText: l10n.filterProviders,
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: providers.isEmpty
                ? Center(child: Text(l10n.selectProvider))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: providers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final p = providers[index];
                      final selected =
                          !widget.hubStyle && p.id == widget.selectedId;
                      final subtitle = p.cli == AppProviderCli.flashskyai
                          ? l10n.providerListModelCount(
                              appCubit.flashskyaiLlmConfigFor(p).models.length,
                            )
                          : l10n.appProviderCliLabel(p.cli);
                      final titleColor = selected
                          ? cs.onPrimaryContainer
                          : cs.onSurface;
                      final subtitleColor = selected
                          ? cs.onPrimaryContainer.withValues(alpha: 0.74)
                          : cs.onSurfaceVariant;
                      final tileColor = selected
                          ? cs.primaryContainer
                          : widget.hubStyle
                          ? cs.workspaceSubtleSurface
                          : cs.workspaceInset;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        tileColor: tileColor,
                        selectedTileColor: cs.primaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        iconColor: titleColor,
                        textColor: titleColor,
                        title: Text(
                          p.name,
                          style: TextStyle(
                            color: titleColor,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: subtitleColor),
                        ),
                        trailing: widget.hubStyle
                            ? Icon(Icons.chevron_right, color: titleColor)
                            : PopupMenuButton<String>(
                                iconColor: titleColor,
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text(l10n.edit),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(l10n.delete),
                                  ),
                                ],
                                onSelected: (action) {
                                  switch (action) {
                                    case 'edit':
                                      widget.onEdit(p);
                                    case 'delete':
                                      widget.onDelete(p.id);
                                  }
                                },
                              ),
                        onTap: () => widget.onSelect(p.id),
                        onLongPress: () => widget.onEdit(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

}
