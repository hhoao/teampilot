import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// Inline find/replace bar for the workbench file editor ([CodeEditor]).
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

  static const double _rowHeight = 34;
  static const double _panelVerticalPadding = 8;
  static const double _panelWidth = 384;
  static const double _findInputWidth = 188;
  static const double _counterWidth = 50;

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
        final cs = Theme.of(context).colorScheme;
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
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(6),
                clipBehavior: Clip.antiAlias,
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: _panelVerticalPadding / 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildFindRow(context, value),
                      if (showReplace) _buildReplaceRow(context, value),
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

  Widget _buildFindRow(BuildContext context, CodeFindValue value) {
    final l10n = context.l10n;
    final hasMatch = value.result?.matches.isNotEmpty ?? false;
    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: [
          _buildTextField(
            context,
            controller: controller.findInputController,
            focusNode: controller.findInputFocusNode,
            hint: l10n.editorFindHint,
          ),
          SizedBox(
            width: _counterWidth,
            child: Text(
              _counterLabel(context, value),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 2),
          _buildToggle(
            context,
            label: 'Aa',
            checked: value.option.caseSensitive,
            tooltip: l10n.editorFindMatchCase,
            onTap: controller.toggleCaseSensitive,
          ),
          _buildToggle(
            context,
            label: '.*',
            checked: value.option.regex,
            tooltip: l10n.editorFindUseRegex,
            onTap: controller.toggleRegex,
          ),
          const SizedBox(width: 2),
          TpIconButton(
            icon: Icons.keyboard_arrow_up,
            size: TpIconButton.kCompactSize,
            compact: true,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            tooltip: l10n.editorFindPrevious,
            enabled: hasMatch,
            onTap: controller.previousMatch,
          ),
          TpIconButton(
            icon: Icons.keyboard_arrow_down,
            size: TpIconButton.kCompactSize,
            compact: true,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            tooltip: l10n.editorFindNext,
            enabled: hasMatch,
            onTap: controller.nextMatch,
          ),
          TpIconButton(
            icon: Icons.close,
            size: TpIconButton.kCompactSize,
            compact: true,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: [
          _buildTextField(
            context,
            controller: controller.replaceInputController,
            focusNode: controller.replaceInputFocusNode,
            hint: l10n.editorFindReplaceHint,
          ),
          const Spacer(),
          TpIconButton(
            icon: Icons.check,
            size: TpIconButton.kCompactSize,
            compact: true,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            tooltip: l10n.editorFindReplaceHint,
            enabled: hasMatch,
            onTap: controller.replaceMatch,
          ),
          TpIconButton(
            icon: Icons.done_all,
            size: TpIconButton.kCompactSize,
            compact: true,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            tooltip: l10n.editorFindReplaceAll,
            enabled: hasMatch,
            onTap: controller.replaceAllMatches,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
  }) {
    final cs = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: color),
    );
    return SizedBox(
      width: _findInputWidth,
      height: _rowHeight,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: 1,
        style: TextStyle(fontSize: 13, color: cs.onSurface),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          filled: true,
          fillColor: cs.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          border: border(cs.outlineVariant),
          enabledBorder: border(cs.outlineVariant),
          focusedBorder: border(cs.primary),
        ),
      ),
    );
  }

  Widget _buildToggle(
    BuildContext context, {
    required String label,
    required bool checked,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: TpHover(
        width: 24,
        height: _rowHeight,
        borderRadius: BorderRadius.circular(4),
        backgroundColor: checked ? cs.primary.withValues(alpha: 0.12) : null,
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
              color: checked ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
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
