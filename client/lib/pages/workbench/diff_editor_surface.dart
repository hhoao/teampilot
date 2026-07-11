import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/editor_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/diff/diff_viewer.dart';
import '../../widgets/workbench/file_diff_surface_toggle.dart';

/// Center-pane git diff for one path + staged|unstaged|changes.
class DiffEditorSurface extends StatefulWidget {
  const DiffEditorSurface({
    required this.workspaceId,
    required this.diffKey,
    super.key,
  });

  final String workspaceId;
  final String diffKey;

  @override
  State<DiffEditorSurface> createState() => _DiffEditorSurfaceState();
}

class _DiffEditorSurfaceState extends State<DiffEditorSurface> {
  var _viewerReady = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _viewerReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = context.select<EditorCubit, DiffTabState?>(
      (c) => c.state.bucket(widget.workspaceId).openDiffs[widget.diffKey],
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
    final reload = context.read<EditorCubit>().diffReloadFor(widget.diffKey);

    return ColoredBox(
      color: cs.workspaceCardChrome(WorkspacePageChrome.workspace),
      child: !_viewerReady
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : DiffViewer.fromUnifiedDiff(
              key: ValueKey(
                Object.hash(widget.diffKey, tab.diffText, tab.title),
              ),
              title: '${tab.title}$stagedLabel',
              diffText: tab.diffText,
              filePath: tab.absolutePath,
              reloadDiff: reload == null
                  ? null
                  : (ignoreWhitespace, fullContext) async {
                      final editor = context.read<EditorCubit>();
                      final next = await reload(
                        ignoreWhitespace,
                        fullContext,
                      );
                      if (next == null || !mounted) return next;
                      editor.updateDiffText(
                        widget.workspaceId,
                        widget.diffKey,
                        next,
                      );
                      return next;
                    },
              onSwitchToFile: () {
                unawaited(
                  switchFileDiffSurface(
                    context: context,
                    workspaceId: widget.workspaceId,
                    absolutePath: tab.absolutePath,
                    target: FileDiffSurfaceMode.file,
                  ),
                );
              },
            ),
    );
  }
}
