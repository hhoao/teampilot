import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ShortcutActivator, SingleActivator, Intent, CallbackAction
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/session/chat_transcript_find_controller.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/find/find_bar_palette.dart';
import '../../widgets/find/find_bar_widgets.dart';

/// Find bar for the chat page: VS Code-style query field with inline
/// Aa / ab / .* toggles + n/N counter + prev/next/close, plus a collapsible
/// results list. Driven by [ChatTranscriptFindController].
class ChatFindBar extends StatefulWidget {
  const ChatFindBar({
    required this.controller,
    required this.queryController,
    required this.focusNode,
    required this.onNavigate,
    required this.onClose,
    super.key,
  });

  final ChatTranscriptFindController controller;
  final TextEditingController queryController;
  final FocusNode focusNode;

  /// Called with the hit to reveal+highlight when the user picks a result or
  /// steps next/prev.
  final void Function(TranscriptHit hit) onNavigate;
  final VoidCallback onClose;

  @override
  State<ChatFindBar> createState() => _ChatFindBarState();
}

class _ChatFindCloseIntent extends Intent {
  const _ChatFindCloseIntent();
}

class _ChatFindBarState extends State<ChatFindBar> {
  static const double _width = 500;

  @override
  void dispose() {
    Debounces.cancel('chat_find_bar_${identityHashCode(this)}');
    super.dispose();
  }

  void _onChanged(String value) {
    Debounces.debounce(
      'chat_find_bar_${identityHashCode(this)}',
      const Duration(milliseconds: 120),
      () {
        if (mounted) widget.controller.search(value);
      },
    );
  }

  void _clear() {
    widget.queryController.clear();
    widget.controller.clear();
  }

  void _navigateCurrent() {
    final hit = widget.controller.current;
    if (hit != null) widget.onNavigate(hit);
  }

  void _navigateIndex(int index) {
    final hits = widget.controller.hits;
    if (index < 0 || index >= hits.length) return;
    widget.controller.select(index);
    widget.onNavigate(hits[index]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Escape closes find. Mounted only while find is visible, so Escape can
    // never open it. (Mirrors TerminalFindShortcuts' Esc handling.)
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape):
            const _ChatFindCloseIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ChatFindCloseIntent: CallbackAction<_ChatFindCloseIntent>(
            onInvoke: (_) {
              widget.onClose();
              return null;
            },
          ),
        },
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final controller = widget.controller;
            final total = controller.hits.length;
            final current = controller.currentIndex;
            final counter = total == 0
                ? l10n.chatFindNoResults
                : '${current + 1}/$total';

            return Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: _width,
                  child: FindBarPanel(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                          child: Row(
                            children: [
                              FindField(
                                width: 300,
                                controller: widget.queryController,
                                focusNode: widget.focusNode,
                                hint: l10n.chatFindHint,
                                autofocus: true,
                                showClear: true,
                                onChanged: _onChanged,
                                onClear: _clear,
                                toggles: [
                                  FindToggleButton(
                                    iconAsset: FindBarIcons.caseSensitive,
                                    tooltip: l10n.chatFindMatchCase,
                                    checked: controller.caseSensitive,
                                    onTap: controller.toggleCaseSensitive,
                                  ),
                                  FindToggleButton(
                                    iconAsset: FindBarIcons.wholeWord,
                                    tooltip: l10n.chatFindWholeWord,
                                    checked: controller.wholeWord,
                                    onTap: controller.toggleWholeWord,
                                  ),
                                  FindToggleButton(
                                    iconAsset: FindBarIcons.regexp,
                                    tooltip: l10n.chatFindUseRegex,
                                    checked: controller.regex,
                                    onTap: controller.toggleRegex,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 4),
                              FindCounterText(
                                label: counter,
                                empty: total == 0,
                                width: 76,
                              ),
                              FindActionButton(
                                icon: Icons.keyboard_arrow_up,
                                tooltip: l10n.chatFindPrevious,
                                enabled: total > 0,
                                onTap: () {
                                  controller.previous();
                                  _navigateCurrent();
                                },
                              ),
                              FindActionButton(
                                icon: Icons.keyboard_arrow_down,
                                tooltip: l10n.chatFindNext,
                                enabled: total > 0,
                                onTap: () {
                                  controller.next();
                                  _navigateCurrent();
                                },
                              ),
                              FindActionButton(
                                icon: Icons.close,
                                tooltip: l10n.chatFindClose,
                                onTap: widget.onClose,
                              ),
                            ],
                          ),
                        ),
                        // The counter already reports "no matches", so the
                        // results list only appears once there are hits.
                        if (total > 0)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  2,
                                  10,
                                  4,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    l10n.chatFindResults,
                                    style: TpTextStyles.of(
                                      context,
                                    ).mdSemibold.copyWith(
                                      color: FindBarPalette.of(
                                        context,
                                      ).mutedText,
                                    ),
                                  ),
                                ),
                              ),
                              _ResultsList(
                                hits: controller.hits,
                                currentIndex: current,
                                query: controller.query,
                                onTap: _navigateIndex,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.hits,
    required this.currentIndex,
    required this.query,
    required this.onTap,
  });

  final List<TranscriptHit> hits;
  final int currentIndex;
  final String query;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: hits.length,
        itemBuilder: (context, index) {
          final hit = hits[index];
          final selected = index == currentIndex;
          return TpHover(
            width: double.infinity,
            borderRadius: BorderRadius.circular(3),
            backgroundColor: selected ? palette.activeBg : null,
            hoverColor: palette.hoverBg,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            onTap: () => onTap(index),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 14,
                  color: palette.mutedText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HighlightedSnippet(
                    text: hit.snippet,
                    query: query,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One-to-two line snippet with the first case-insensitive [query] occurrence
/// in bold (mirrors `workspace_search_dialog.dart`).
class _HighlightedSnippet extends StatelessWidget {
  const _HighlightedSnippet({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    final style = TpTextStyles.of(context).md.copyWith(color: palette.mutedText);
    final q = query.trim();
    if (q.isEmpty) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final match = RegExp(
      RegExp.escape(q),
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final start = match.start;
    final end = match.end;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: style.copyWith(
              fontWeight: FontWeight.w600,
              color: palette.focusBorder,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
