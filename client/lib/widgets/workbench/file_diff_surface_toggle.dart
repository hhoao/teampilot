import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../cubits/git_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/git/git_repo_store.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import 'package:shared_ui/shared_ui.dart';

/// Which surface the center pane is showing for a path.
enum FileDiffSurfaceMode { file, diff }

/// Compact File | Diff pill (Orca Edit | Changes), right-aligned in toolbars.
class FileDiffSurfaceToggle extends StatelessWidget {
  const FileDiffSurfaceToggle({
    required this.mode,
    required this.onModeChanged,
    this.enabled = true,
    super.key,
  });

  final FileDiffSurfaceMode mode;
  final ValueChanged<FileDiffSurfaceMode> onModeChanged;
  final bool enabled;

  static const double _size = TpIconButton.kCompactSize;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final color = cs.tpIconMuted;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Container(
        height: _size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Segment(
              icon: Icons.description_outlined,
              tooltip: l10n.fileDiffToggleFile,
              selected: mode == FileDiffSurfaceMode.file,
              color: color,
              onTap: enabled
                  ? () => onModeChanged(FileDiffSurfaceMode.file)
                  : null,
            ),
            Container(width: 1, height: 14, color: cs.outlineVariant),
            _Segment(
              icon: Icons.difference_outlined,
              tooltip: l10n.fileDiffToggleDiff,
              selected: mode == FileDiffSurfaceMode.diff,
              color: color,
              onTap: enabled
                  ? () => onModeChanged(FileDiffSurfaceMode.diff)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? cs.onSurface.withValues(alpha: 0.12)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: color.withValues(alpha: 0.12),
          splashColor: color.withValues(alpha: 0.2),
          child: SizedBox(
            width: 30,
            height: FileDiffSurfaceToggle._size,
            child: Icon(icon, size: context.tpIconSizes.sm, color: color),
          ),
        ),
      ),
    );
  }
}

/// Resolves the [GitCubit] whose repo root contains [absolutePath], if any.
GitCubit? gitCubitForAbsolutePath(BuildContext context, String absolutePath) {
  final scope = WorkspaceToolsScope.maybeOf(context);
  final tools = scope?.tools;
  if (scope == null || tools == null || scope.roots.isEmpty) return null;
  final root = _longestRootContaining(scope.roots, absolutePath);
  if (root == null) return null;
  return context.read<GitRepoStore>().cubitFor(
    root,
    workContext: tools.context,
  );
}

String? _longestRootContaining(List<String> roots, String absolutePath) {
  final ctx = p.Context();
  final normalized = ctx.normalize(absolutePath);
  String? best;
  var bestLen = -1;
  for (final root in roots) {
    if (root.isEmpty) continue;
    final nRoot = ctx.normalize(root);
    if (normalized == nRoot || ctx.isWithin(nRoot, normalized)) {
      if (nRoot.length > bestLen) {
        best = nRoot;
        bestLen = nRoot.length;
      }
    }
  }
  return best;
}

/// Switches the center pane between file edit and uncommitted (HEAD) diff.
Future<void> switchFileDiffSurface({
  required BuildContext context,
  required String workspaceId,
  required String absolutePath,
  required FileDiffSurfaceMode target,
}) async {
  final opener = context.read<WorkbenchEditorOpener>();
  if (target == FileDiffSurfaceMode.file) {
    await opener.openFile(workspaceId, absolutePath, preview: true);
    return;
  }
  final git = gitCubitForAbsolutePath(context, absolutePath);
  if (git == null) return;
  final root = git.state.repoRoot;
  if (root.isEmpty) return;
  final relative = p.Context().relative(absolutePath, from: root);
  if (relative.startsWith('..')) return;
  await opener.openChangesDiff(
    workspaceId: workspaceId,
    absolutePath: absolutePath,
    title: p.basename(absolutePath),
    loadDiff: ({ignoreWhitespace = false, fullContext = false}) =>
        git.diffAgainstHead(
          relative,
          ignoreWhitespace: ignoreWhitespace,
          fullContext: fullContext,
        ),
  );
}
