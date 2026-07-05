import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/extension_cubit.dart';
import '../../../../cubits/workspace_project_config_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../team_config/team_config_extensions_section.dart';

class WorkspaceExtensionsSection extends StatelessWidget {
  const WorkspaceExtensionsSection({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final projectState = context.watch<WorkspaceProjectConfigCubit>().state;
    if (projectState.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final rows = context.watch<ExtensionCubit>().state.rows;
    final overrides = projectState.config.extensionOverrides;
    final projectCubit = context.read<WorkspaceProjectConfigCubit>();

    ExtensionOverrideChoice choiceFor(String id) {
      if (!overrides.containsKey(id)) {
        return ExtensionOverrideChoice.followGlobal;
      }
      return overrides[id]!
          ? ExtensionOverrideChoice.forceOn
          : ExtensionOverrideChoice.forceOff;
    }

    bool effective(ExtensionRow row) {
      final override = overrides[row.id];
      return override ?? row.globalEnabled;
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(title: l10n.workspaceExtensionsTitle),
                const SizedBox(height: 6),
                Text(
                  l10n.workspaceExtensionsSubtitle,
                  style: AppTextStyles.of(context).bodySmall.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 14),
                for (final row in rows)
                  TeamExtensionRow(
                    row: row,
                    choice: choiceFor(row.id),
                    effective: effective(row),
                    onChoice: (choice) {
                      final value = switch (choice) {
                        ExtensionOverrideChoice.followGlobal => null,
                        ExtensionOverrideChoice.forceOn => true,
                        ExtensionOverrideChoice.forceOff => false,
                      };
                      projectCubit.setExtensionOverride(row.id, value);
                    },
                    effectiveOnLabel: l10n.workspaceExtensionEffectiveOn,
                    effectiveOffLabel: l10n.workspaceExtensionEffectiveOff,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
