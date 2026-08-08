import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/find/find_bar_palette.dart';
import '../../widgets/find/find_bar_widgets.dart';

/// Inline find/replace bar for the workbench file editor ([CodeEditor]),
/// styled like the VS Code find widget.
///
/// Rendered via [CodeEditor.findBuilder] and bound to re-editor's
/// [CodeFindController]. Collapses to nothing while the find bar is closed
/// so the editor layout stays unchanged (see re-editor's `find` slot, which
/// reads [preferredSize] to pad the code field).
class CodeEditorFindPanel extends StatelessWidget
    implements PreferredSizeWidget {
  const CodeEditorFindPanel({
    required this.controller,
    required this.readOnly,
    super.key,
  });

  final CodeFindController controller;
  final bool readOnly;

  static const double _rowHeight = 26;
  static const double _panelVerticalPadding = 8;
  static const double _panelWidth = 452;
  static const double _findFieldWidth = 260;
  static const double _counterWidth = 76;
  static const double _buttonSize = 22;
  static const double _chevronWidth = 16;

  @override
  Size get preferredSize {
    final value = controller.value;
    if (value == null) {
      return const Size(double.infinity, 0);
    }
    final rows = value.replaceMode && !readOnly ? 2 : 1;
    return Size(double.infinity, rows * _rowHeight + _panelVerticalPadding);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final value = controller.value;
        if (value == null) {
          return const SizedBox(width: 0, height: 0);
        }
        final showReplace = value.replaceMode && !readOnly;
        return Container(
          margin: const EdgeInsets.only(right: 12),
          alignment: Alignment.topRight,
          height: preferredSize.height,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _panelWidth,
              height: preferredSize.height,
              child: FindBarPanel(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildChevronToggle(context, showReplace),
                      const SizedBox(width: 2),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFindRow(context, value),
                          if (showReplace) _buildReplaceRow(context, value),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChevronToggle(BuildContext context, bool expanded) {
    final palette = FindBarPalette.of(context);
    return Tooltip(
      message: context.l10n.editorFindToggleReplace,
      child: TpHover(
        width: _chevronWidth,
        height: _rowHeight,
        borderRadius: BorderRadius.circular(3),
        hoverColor: palette.hoverBg,
        onTap: controller.toggleMode,
        child: AnimatedRotation(
          turns: expanded ? 0.25 : 0,
          duration: const Duration(milliseconds: 120),
          child: Icon(Icons.chevron_right, size: 14, color: palette.icon),
        ),
      ),
    );
  }

  Widget _buildFindRow(BuildContext context, CodeFindValue value) {
    final l10n = context.l10n;
    final hasMatch = value.result?.matches.isNotEmpty ?? false;
    return SizedBox(
      height: _rowHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FindField(
            width: _findFieldWidth,
            controller: controller.findInputController,
            focusNode: controller.findInputFocusNode,
            hint: l10n.editorFindHint,
            toggles: [
              FindToggleButton(
                iconAsset: FindBarIcons.caseSensitive,
                tooltip: l10n.editorFindMatchCase,
                checked: value.option.caseSensitive,
                onTap: controller.toggleCaseSensitive,
              ),
              FindToggleButton(
                iconAsset: FindBarIcons.wholeWord,
                tooltip: l10n.editorFindWholeWord,
                checked: value.option.wholeWord,
                onTap: controller.toggleWholeWord,
              ),
              FindToggleButton(
                iconAsset: FindBarIcons.regexp,
                tooltip: l10n.editorFindUseRegex,
                checked: value.option.regex,
                onTap: controller.toggleRegex,
              ),
            ],
          ),
          const SizedBox(width: 4),
          FindCounterText(
            label: _counterLabel(context, value),
            empty: !hasMatch && value.option.pattern.isNotEmpty,
            width: _counterWidth,
          ),
          const SizedBox(width: 2),
          FindActionButton(
            icon: Icons.keyboard_arrow_up,
            tooltip: l10n.editorFindPrevious,
            enabled: hasMatch,
            onTap: controller.previousMatch,
          ),
          FindActionButton(
            icon: Icons.keyboard_arrow_down,
            tooltip: l10n.editorFindNext,
            enabled: hasMatch,
            onTap: controller.nextMatch,
          ),
          FindActionButton(
            icon: Icons.filter_alt,
            tooltip: l10n.editorFindInSelection,
            enabled: hasMatch && controller.canFindInSelection,
            checked: value.option.findInSelection,
            onTap: controller.toggleFindInSelection,
          ),
          FindActionButton(
            icon: Icons.close,
            tooltip: l10n.editorFindClose,
            onTap: controller.close,
          ),
        ],
      ),
    );
  }

  Widget _buildReplaceRow(BuildContext context, CodeFindValue value) {
    final l10n = context.l10n;
    final hasMatch = value.result?.matches.isNotEmpty ?? false;
    // Mirror the find row's trailing section (counter + buttons) so the
    // replace actions sit right-aligned under the find buttons.
    final trailingWidth = _counterWidth + 2 + 4 * _buttonSize;
    return SizedBox(
      height: _rowHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FindField(
            width: _findFieldWidth,
            controller: controller.replaceInputController,
            focusNode: controller.replaceInputFocusNode,
            hint: l10n.editorFindReplaceHint,
            toggles: [
              FindToggleButton(
                iconAsset: FindBarIcons.upperCase,
                tooltip: l10n.editorFindReplacePreserveCase,
                checked: value.option.preserveCase,
                onTap: controller.togglePreserveCase,
              ),
            ],
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: trailingWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FindActionButton(
                    key: const ValueKey('editor-replace-one'),
                    assetPath: FindBarIcons.replace,
                    tooltip: l10n.editorFindReplaceOne,
                    enabled: hasMatch,
                    onTap: controller.replaceMatch,
                  ),
                  FindActionButton(
                    key: const ValueKey('editor-replace-all'),
                    assetPath: FindBarIcons.replaceAll,
                    tooltip: l10n.editorFindReplaceAll,
                    enabled: hasMatch,
                    onTap: controller.replaceAllMatches,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _counterLabel(BuildContext context, CodeFindValue value) {
    if (value.option.pattern.isEmpty) {
      return '';
    }
    final result = value.result;
    if (result != null && result.matches.isNotEmpty) {
      return '${result.index + 1}/${result.matches.length}';
    }
    return context.l10n.editorFindNoResults;
  }
}
