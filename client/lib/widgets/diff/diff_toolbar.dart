import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/workspace_surface_layers.dart';
import '../workbench/file_diff_surface_toggle.dart';
import 'diff_view_controller.dart';

/// Which diff layout the viewer is showing.
enum DiffViewMode { sideBySide, unified }

/// Toolbar for the diff viewer: optional title on the left; compact icon
/// actions and a pill mode switch on the right.
class DiffToolbar extends StatelessWidget {
  const DiffToolbar({
    required this.controller,
    required this.mode,
    required this.onModeChanged,
    required this.ignoreWhitespace,
    required this.onIgnoreWhitespaceChanged,
    this.chrome = WorkspacePageChrome.workspace,
    this.showIgnoreWhitespace = true,
    this.fullContext = false,
    required this.onFullContextChanged,
    this.showFullContext = false,
    this.onOpenSource,
    this.onSwitchToFile,
    this.title,
    this.isDirty = false,
    this.onSave,
    super.key,
  });

  final DiffViewController controller;
  final DiffViewMode mode;
  final ValueChanged<DiffViewMode> onModeChanged;
  final bool ignoreWhitespace;
  final ValueChanged<bool> onIgnoreWhitespaceChanged;
  final WorkspacePageChrome chrome;
  final bool showIgnoreWhitespace;

  /// When true, the whole file is shown; otherwise only changed regions.
  final bool fullContext;
  final ValueChanged<bool> onFullContextChanged;
  final bool showFullContext;

  /// Opens the underlying file in the editor. Hidden when null or when
  /// [onSwitchToFile] is set (the File|Diff pill replaces it).
  final VoidCallback? onOpenSource;

  /// When set, shows a File|Diff pill (Diff selected) at the far right.
  final VoidCallback? onSwitchToFile;

  /// Optional leading title (e.g. file name). Tools stay right-aligned.
  final String? title;

  final bool isDirty;
  final VoidCallback? onSave;

  static const double _actionSize = TpIconButton.kCompactSize;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final titleText = title?.trim();
    final iconColor = cs.tpIconMuted;
    final showOpenSource = onOpenSource != null && onSwitchToFile == null;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.workspaceCardChrome(chrome),
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          if (titleText != null && titleText.isNotEmpty)
            Expanded(
              child: Text(
                titleText,
                style: styles.sm,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          if (isDirty && onSave != null)
            TpIconButton(
              icon: Icons.save_outlined,
              tooltip: l10n.editorSave,
              size: _actionSize,
              compact: true,
              color: iconColor,
              onTap: onSave,
            ),
          if (showOpenSource)
            TpIconButton(
              icon: Icons.description_outlined,
              tooltip: l10n.diffOpenSourceFile,
              size: _actionSize,
              compact: true,
              color: iconColor,
              onTap: onOpenSource,
            ),
          if (showFullContext)
            _DiffToolbarIconToggle(
              icon: Icons.unfold_more,
              tooltip: l10n.diffShowAllLines,
              selected: fullContext,
              color: iconColor,
              onChanged: onFullContextChanged,
            ),
          if (showIgnoreWhitespace)
            _DiffToolbarIconToggle(
              icon: Icons.space_bar,
              tooltip: l10n.diffIgnoreWhitespace,
              selected: ignoreWhitespace,
              color: iconColor,
              onChanged: onIgnoreWhitespaceChanged,
            ),
          const SizedBox(width: 4),
          _DiffModePill(
            mode: mode,
            onModeChanged: onModeChanged,
            sideBySideTooltip: l10n.diffViewSideBySide,
            unifiedTooltip: l10n.diffViewUnified,
            color: iconColor,
          ),
          const SizedBox(width: 2),
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final total = controller.changeCount;
              final enabled = total > 0;
              final current = controller.current < 0
                  ? 0
                  : controller.current + 1;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TpIconButton(
                    icon: Icons.keyboard_arrow_up,
                    tooltip: l10n.diffPreviousChange,
                    size: _actionSize,
                    compact: true,
                    color: iconColor,
                    enabled: enabled,
                    onTap: enabled ? controller.previous : null,
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 44),
                    child: Text(
                      enabled
                          ? l10n.diffChangeCounter(current, total)
                          : l10n.diffNoChanges,
                      textAlign: TextAlign.center,
                      style: styles.mutedSm,
                    ),
                  ),
                  TpIconButton(
                    icon: Icons.keyboard_arrow_down,
                    tooltip: l10n.diffNextChange,
                    size: _actionSize,
                    compact: true,
                    color: iconColor,
                    enabled: enabled,
                    onTap: enabled ? controller.next : null,
                  ),
                ],
              );
            },
          ),
          if (onSwitchToFile != null) ...[
            const SizedBox(width: 4),
            FileDiffSurfaceToggle(
              mode: FileDiffSurfaceMode.diff,
              onModeChanged: (m) {
                if (m == FileDiffSurfaceMode.file) onSwitchToFile!();
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Pill segmented control matching editor chrome (border + selected fill).
class _DiffModePill extends StatelessWidget {
  const _DiffModePill({
    required this.mode,
    required this.onModeChanged,
    required this.sideBySideTooltip,
    required this.unifiedTooltip,
    required this.color,
  });

  final DiffViewMode mode;
  final ValueChanged<DiffViewMode> onModeChanged;
  final String sideBySideTooltip;
  final String unifiedTooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: DiffToolbar._actionSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DiffModeSegment(
            icon: Icons.view_column_outlined,
            tooltip: sideBySideTooltip,
            selected: mode == DiffViewMode.sideBySide,
            color: color,
            onTap: () => onModeChanged(DiffViewMode.sideBySide),
          ),
          Container(width: 1, height: 14, color: cs.outlineVariant),
          _DiffModeSegment(
            icon: Icons.view_agenda_outlined,
            tooltip: unifiedTooltip,
            selected: mode == DiffViewMode.unified,
            color: color,
            onTap: () => onModeChanged(DiffViewMode.unified),
          ),
        ],
      ),
    );
  }
}

class _DiffModeSegment extends StatelessWidget {
  const _DiffModeSegment({
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: TpHover(
        backgroundColor: selected
            ? cs.onSurface.withValues(alpha: 0.12)
            : Colors.transparent,
        width: 30,
        height: DiffToolbar._actionSize,
        hoverColor: color.withValues(alpha: 0.12),
        splashColor: color.withValues(alpha: 0.2),
        onTap: onTap,
        child: Center(
          child: Icon(icon, size: context.tpIconSizes.sm, color: color),
        ),
      ),
    );
  }
}

/// Icon on/off toggle with selected fill — same density as [TpIconButton].
class _DiffToolbarIconToggle extends StatelessWidget {
  const _DiffToolbarIconToggle({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.color,
    required this.onChanged,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color color;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TpIconButton(
      icon: icon,
      tooltip: tooltip,
      size: DiffToolbar._actionSize,
      compact: true,
      color: color,
      backgroundColor: selected ? cs.onSurface.withValues(alpha: 0.12) : null,
      onTap: () => onChanged(!selected),
    );
  }
}
