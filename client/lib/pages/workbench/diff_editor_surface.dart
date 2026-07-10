import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/diff/diff_viewer.dart';

/// Center-pane git diff for one path + staged|unstaged.
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

    final stagedLabel = tab.staged ? ' (staged)' : '';
    final reload = context.read<EditorCubit>().diffReloadFor(widget.diffKey);

    return ColoredBox(
      color: cs.workspaceCardChrome(WorkspacePageChrome.workspace),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${tab.title}$stagedLabel',
                  style: AppTextStyles.of(context).body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: !_viewerReady
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : tab.diffText.trim().isEmpty
                ? Center(child: Text(context.l10n.diffNoChanges))
                : DiffViewer.fromUnifiedDiff(
                    key: ValueKey(
                      Object.hash(widget.diffKey, tab.diffText, tab.title),
                    ),
                    diffText: tab.diffText,
                    filePath: tab.absolutePath,
                    reloadDiff: reload == null
                        ? null
                        : (ignoreWhitespace, fullContext) async {
                            final next = await reload(
                              ignoreWhitespace,
                              fullContext,
                            );
                            if (next != null && mounted) {
                              context.read<EditorCubit>().updateDiffText(
                                widget.workspaceId,
                                widget.diffKey,
                                next,
                              );
                            }
                            return next;
                          },
                    onOpenSource: () {
                      context.read<WorkbenchEditorOpener>().openFile(
                        widget.workspaceId,
                        tab.absolutePath,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
