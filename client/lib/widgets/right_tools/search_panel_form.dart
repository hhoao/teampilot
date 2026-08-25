import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../find/find_bar_palette.dart';
import '../find/find_bar_widgets.dart';

/// Chevron that expands/collapses the replace row, like the VS Code search
/// view's left-edge toggle.
class SearchPanelChevron extends StatelessWidget {
  const SearchPanelChevron({
    required this.expanded,
    required this.onTap,
    super.key,
  });

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    return Tooltip(
      message: context.l10n.editorFindToggleReplace,
      child: TpHover(
        width: 16,
        height: FindField.kHeight,
        borderRadius: BorderRadius.circular(3),
        hoverColor: palette.hoverBg,
        onTap: onTap,
        child: AnimatedRotation(
          turns: expanded ? 0.25 : 0,
          duration: const Duration(milliseconds: 120),
          child: Icon(Icons.chevron_right, size: 14, color: palette.icon),
        ),
      ),
    );
  }
}

/// `...` toggle for the search details section; stays highlighted while
/// non-default filters (include/exclude globs, gitignore off) are active.
class SearchPanelDetailsToggle extends StatelessWidget {
  const SearchPanelDetailsToggle({
    required this.expanded,
    required this.highlighted,
    required this.onTap,
    super.key,
  });

  final bool expanded;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FindActionButton(
      icon: Icons.more_horiz,
      tooltip: context.l10n.workspaceSearchToggleDetails,
      checked: expanded || highlighted,
      onTap: onTap,
    );
  }
}

/// Include/exclude glob fields + gitignore switch shown under the `...`
/// toggle (the VS Code search details body).
class SearchPanelDetailsSection extends StatelessWidget {
  const SearchPanelDetailsSection({
    required this.includeController,
    required this.includeFocusNode,
    required this.excludeController,
    required this.excludeFocusNode,
    required this.useGitignore,
    required this.onGlobChanged,
    required this.onGitignoreChanged,
    super.key,
  });

  final TextEditingController includeController;
  final FocusNode includeFocusNode;
  final TextEditingController excludeController;
  final FocusNode excludeFocusNode;
  final bool useGitignore;
  final ValueChanged<String> onGlobChanged;
  final ValueChanged<bool> onGitignoreChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = FindBarPalette.of(context);
    final styles = TpTextStyles.of(context);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(text, style: styles.xsColored(palette.mutedText)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label(l10n.workspaceSearchFilesToInclude),
        FindField(
          controller: includeController,
          focusNode: includeFocusNode,
          hint: l10n.workspaceSearchIncludeHint,
          onChanged: onGlobChanged,
        ),
        const SizedBox(height: 8),
        label(l10n.workspaceSearchFilesToExclude),
        FindField(
          controller: excludeController,
          focusNode: excludeFocusNode,
          hint: l10n.workspaceSearchExcludeHint,
          onChanged: onGlobChanged,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: useGitignore,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onGitignoreChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 6),
            Text(l10n.workspaceSearchUseGitignore, style: styles.sm),
          ],
        ),
      ],
    );
  }
}
