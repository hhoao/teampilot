import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/editor_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/diff/diff_viewer.dart';
import '../../widgets/workbench/file_diff_surface_toggle.dart';

/// Center-pane git diff for one path + staged|unstaged|changes.
class DiffEditorSurface extends StatelessWidget {
  const DiffEditorSurface({
    required this.workspaceId,
    required this.diffKey,
    super.key,
  });

  final String workspaceId;
  final String diffKey;

  @override
  Widget build(BuildContext context) {
    final tab = context.select<EditorCubit, DiffTabState?>(
      (c) => c.state.bucket(workspaceId).openDiffs[diffKey],
    );
    final cs = Theme.of(context).colorScheme;
    if (tab == null) {
      return ColoredBox(
        color: cs.workspaceCard,
        child: Center(child: Text(context.l10n.diffNoChanges)),
      );
    }

    final stagedLabel = tab.source == WorkbenchDiffSource.staged
        ? ' (staged)'
        : '';
    final reload = context.read<EditorCubit>().diffReloadFor(diffKey);

    return ColoredBox(
      color: cs.workspaceCardChrome(WorkspacePageChrome.workspace),
      child: DiffViewer.fromUnifiedDiff(
        key: ValueKey(Object.hash(diffKey, tab.diffText, tab.title)),
        title: '${tab.title}$stagedLabel',
        diffText: tab.diffText,
        filePath: tab.absolutePath,
        reloadDiff: reload == null
            ? null
            : (ignoreWhitespace, fullContext) async {
                final editor = context.read<EditorCubit>();
                final next = await reload(ignoreWhitespace, fullContext);
                if (next == null || !context.mounted) return next;
                editor.updateDiffText(workspaceId, diffKey, next);
                return next;
              },
        onSwitchToFile: () {
          unawaited(
            switchFileDiffSurface(
              context: context,
              workspaceId: workspaceId,
              absolutePath: tab.absolutePath,
              target: FileDiffSurfaceMode.file,
            ),
          );
        },
      ),
    );
  }
}
