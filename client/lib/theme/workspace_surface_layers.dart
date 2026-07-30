import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Which workspace-home route family chrome paints with.
///
/// Home and workspace views swap page vs card surfaces so the floated card reads
/// against a contrasting backdrop on each route.
enum WorkspacePageChrome { home, workspace }

/// Material 3 surface nesting for workspace-style UI.
///
/// Level 0 [workspacePage] -> scaffold / split backdrop.
/// Level 1 [workspaceSubtleSurface] -> quiet panels or rows directly on page.
/// Level 2 [workspaceCard] -> list & detail shells, settings cards.
/// Level 3 [workspaceInset] -> rows, chips, controls inside a card.
/// Level 4 [workspaceCode] -> JSON / code blocks.
extension WorkspaceSurfaceLayers on ColorScheme {
  /// Default page backdrop (home chrome). Prefer [workspacePageChrome] in routed UI.
  Color get workspacePage => surface;

  Color get workspaceSubtleSurface => surfaceContainerLow;

  /// Default card shell fill (home chrome). Prefer [workspaceCardChrome] in routed UI.
  Color get workspaceCard => surfaceContainer;

  Color get workspaceInset => surfaceContainerHigh;

  Color get workspaceCode => surfaceContainerHighest;

  Color workspacePageChrome(WorkspacePageChrome chrome) => switch (chrome) {
    WorkspacePageChrome.home => surface,
    WorkspacePageChrome.workspace => surfaceContainer,
  };

  Color workspaceCardChrome(WorkspacePageChrome chrome) => switch (chrome) {
    WorkspacePageChrome.home => surfaceContainer,
    WorkspacePageChrome.workspace => surface,
  };

  /// Primary list/row label — prefer over hardcoded gray-900 / white pairs.
  Color get workspacePrimaryText => onSurface;

  /// Secondary/muted label — prefer over hardcoded gray-500 / white70 pairs.
  Color get workspaceMutedText => onSurfaceVariant;
}

BoxDecoration workspaceCardDecoration(
  ColorScheme cs, {
  double radius = 10,
  double borderAlpha = 1,
}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: cs.outlineVariant.withValues(alpha: borderAlpha)),
  );
}

BoxDecoration workspaceInsetDecoration(ColorScheme cs, {double radius = 8}) {
  return BoxDecoration(
    color: cs.workspaceInset,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
  );
}

BoxDecoration workspaceCodeDecoration(ColorScheme cs, {double radius = 8}) {
  return BoxDecoration(
    color: cs.workspaceCode,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
  );
}

/// Floats [child] as a single rounded card on the workspace page backdrop.
///
/// Used by [HomePage] and [WorkspacePage] so home and
/// workspace views share the same outer chrome (padding, shadow, border).
/// Bottom inset is omitted by default; the transparent status bar adds a
/// small chrome breath above/below itself instead.
class WorkspacePageCardShell extends StatelessWidget {
  const WorkspacePageCardShell({
    required this.child,
    this.chrome = WorkspacePageChrome.home,
    this.omitLeftPadding = false,
    this.omitHorizontalPadding = false,
    this.omitBottomPadding = true,
    super.key,
  });

  final Widget child;
  final WorkspacePageChrome chrome;

  /// When true, drops the left inset (legacy rail flush layout).
  final bool omitLeftPadding;

  /// When true, drops left and right insets (full-bleed card). Also applied
  /// automatically when [TpSidebarScope.isMobile] is true.
  final bool omitHorizontalPadding;

  /// When true (default), drops the card bottom inset; status-bar vertical
  /// inset provides the small gap instead. Corners stay rounded.
  final bool omitBottomPadding;

  static const EdgeInsets padding = EdgeInsets.fromLTRB(16, 0, 16, 16);
  static const double radius = 16;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);
    final isMobile = TpSidebarScope.maybeOf(context)?.isMobile ?? false;
    final flushHorizontal = omitHorizontalPadding || isMobile;
    var inset = flushHorizontal
        ? padding.copyWith(left: 0, right: 0)
        : (omitLeftPadding ? padding.copyWith(left: 0) : padding);
    if (omitBottomPadding) {
      inset = inset.copyWith(bottom: 0);
    }

    // Card fill must be [Material], not a colored [DecoratedBox]/[Container].
    // ListTile paints tileColor / ink on the nearest Material; an opaque
    // DecoratedBox between ListTile and that Material triggers Flutter's
    // "ink splashes may be invisible" assertion and hides those effects.
    return ColoredBox(
      color: cs.workspacePageChrome(chrome),
      child: Padding(
        padding: inset,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          // Border drawn in front of the children so edge-to-edge sidebar /
          // content surfaces can't paint over it; also makes rounded corners
          // read against the near-identical page background.
          foregroundDecoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: Material(
            color: cs.workspaceCardChrome(chrome),
            child: child,
          ),
        ),
      ),
    );
  }
}
