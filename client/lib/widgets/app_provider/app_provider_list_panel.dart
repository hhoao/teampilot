import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../utils/app_keys.dart';
import '../app_outline_text_field.dart';

class AppProviderListPanel extends StatefulWidget {
  const AppProviderListPanel({
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.hubStyle = false,
    super.key,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
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

    return Container(
      key: AppKeys.llmProviderList,
      decoration: widget.hubStyle
          ? null
          : BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant),
            ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.providerList,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onAdd,
                  child: Text('+ ${l10n.add}'),
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
                      final modelCount = p.enables(AppProviderTool.flashskyai)
                          ? appCubit.flashskyaiLlmConfigFor(p).models.length
                          : 0;
                      final subtitle = p.enables(AppProviderTool.flashskyai)
                          ? l10n.providerListModelCount(modelCount)
                          : p.enabledTools
                                .map((t) => _toolLabel(l10n, t))
                                .join(' · ');
                      return Material(
                        color: selected ? cs.primaryContainer : cs.surface,
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          dense: true,
                          title: Text(p.name),
                          subtitle: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: widget.hubStyle
                              ? const Icon(Icons.chevron_right)
                              : PopupMenuButton<String>(
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _toolLabel(dynamic l10n, AppProviderTool tool) {
    return switch (tool) {
      AppProviderTool.flashskyai => l10n.appProviderToolFlashskyai,
      AppProviderTool.codex => l10n.appProviderToolCodex,
      AppProviderTool.claude => l10n.appProviderToolClaude,
    };
  }
}
