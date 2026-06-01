import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/llm_config_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/app_provider/app_provider_list_panel.dart';
import 'llm_config_helpers.dart';
import 'llm_config_routes.dart';

class LlmProvidersListContent extends StatelessWidget {
  const LlmProvidersListContent({super.key, 
    required this.controller,
    this.hubStyle = false,
    this.onSelected,
    this.onAdd,
    this.onEdit,
  });

  final LlmConfigCubit controller;
  final bool hubStyle;
  final VoidCallback? onSelected;
  final VoidCallback? onAdd;
  final ValueChanged<AppProviderConfig>? onEdit;

  @override
  Widget build(BuildContext context) {
    final appCubit = context.watch<AppProviderCubit>();
    final selectedId = appCubit.state.selectedId;
    return AppProviderListPanel(
      selectedId: hubStyle ? null : selectedId,
      hubStyle: hubStyle,
      onSelect: (id) {
        appCubit.selectProvider(id);
        onSelected?.call();
        if (hubStyle) {
          context.push(llmProviderConfigRoute(appCubit.state.selectedCli, id));
        }
      },
      onAdd:
          onAdd ??
          () => context.push(llmProviderAddRoute(appCubit.state.selectedCli)),
      onImport: () async {
        final result = await context
            .read<AppProviderCubit>()
            .importFromExternal();
        if (!context.mounted) return;
        final l10n = context.l10n;
        final changed = result.added + result.updated;
        final message = changed == 0 && result.mirroredToFlashskyai == 0
            ? l10n.appProviderImportNothing
            : l10n.appProviderImportSuccess(
                changed,
                result.mirroredToFlashskyai,
                result.mirrorSkipped,
              );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      },
      onEdit: (provider) {
        if (onEdit != null) {
          onEdit!(provider);
          return;
        }
        context.push(llmProviderEditRoute(provider.cli, provider.id));
      },
      onDelete: (id) => confirmDeleteAppProvider(context, id),
    );
  }
}

/// 右侧详情/模型面板外框，与左侧 [AppProviderListPanel] 列表卡片一致。
class LlmWorkspaceDetailCard extends StatelessWidget {
  const LlmWorkspaceDetailCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: workspaceCardDecoration(cs),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
