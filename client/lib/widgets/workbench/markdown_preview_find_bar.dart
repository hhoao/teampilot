import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/editor/markdown_preview_find_controller.dart';
import '../find/find_bar_widgets.dart';

/// VS Code-style find bar for the markdown preview pane ([CodeEditorFindPanel]
/// single-row layout), bound to a [MarkdownPreviewFindController].
///
/// The field text is the source of truth for query input; controller state
/// flows back one-way into the counter / hit-dependent affordances. Keyboard:
/// Escape closes, Enter advances, Shift+Enter goes back.
class MarkdownPreviewFindBar extends StatefulWidget {
  const MarkdownPreviewFindBar({required this.controller, super.key});

  final MarkdownPreviewFindController controller;

  @override
  State<MarkdownPreviewFindBar> createState() =>
      _MarkdownPreviewFindBarState();
}

class _MarkdownPreviewFindBarState extends State<MarkdownPreviewFindBar> {
  late final TextEditingController _field;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    // Seed once from an existing query so reopening restores the last search.
    _field = TextEditingController(text: widget.controller.query);
    _focus = FocusNode(onKeyEvent: _onKey);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.controller.close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.controller.previous();
      } else {
        widget.controller.next();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final l10n = context.l10n;
        final noResults = c.hasError || c.hits.isEmpty;
        return FindBarPanel(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FindField(
                  controller: _field,
                  focusNode: _focus,
                  hint: l10n.editorFindHint,
                  autofocus: true,
                  width: 240,
                  onChanged: c.search,
                  toggles: [
                    FindToggleButton(
                      iconAsset: FindBarIcons.caseSensitive,
                      tooltip: l10n.editorFindMatchCase,
                      checked: c.caseSensitive,
                      onTap: c.toggleCaseSensitive,
                    ),
                    FindToggleButton(
                      iconAsset: FindBarIcons.regexp,
                      tooltip: l10n.editorFindUseRegex,
                      checked: c.regex,
                      onTap: c.toggleRegex,
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                FindCounterText(
                  label: noResults ? l10n.editorFindNoResults : c.counterLabel(),
                  empty: noResults,
                ),
                FindActionButton(
                  tooltip: l10n.editorFindPrevious,
                  icon: Icons.keyboard_arrow_up_rounded,
                  enabled: !noResults,
                  onTap: c.previous,
                ),
                FindActionButton(
                  tooltip: l10n.editorFindNext,
                  icon: Icons.keyboard_arrow_down_rounded,
                  enabled: !noResults,
                  onTap: c.next,
                ),
                FindActionButton(
                  tooltip: l10n.editorFindClose,
                  icon: Icons.close_rounded,
                  onTap: c.close,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
