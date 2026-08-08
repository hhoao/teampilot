import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ShortcutActivator, SingleActivator, Intent, CallbackAction
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/session/chat_transcript_find_controller.dart';
import '../../utils/debounce/debounce.dart';

/// Find bar for the chat page: query field + n/N counter + prev/next + close,
/// plus a collapsible results list. Driven by [ChatTranscriptFindController].
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
  static const double _rowHeight = 34;
  static const double _width = 420;

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
    final cs = Theme.of(context).colorScheme;
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
            final counter = total == 0 ? '' : '${current + 1}/$total';
            final hasQuery = controller.hasQuery;

            return Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(6),
                  clipBehavior: Clip.antiAlias,
                  color: cs.surfaceContainerHighest,
                  child: SizedBox(
                    width: _width,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: _rowHeight,
                          child: Row(
                            children: [
                              _input(context),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  counter,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TpIconButton(
                                icon: Icons.keyboard_arrow_up,
                                size: TpIconButton.kCompactSize,
                                compact: true,
                                color: cs.onSurfaceVariant,
                                tooltip: l10n.chatFindPrevious,
                                enabled: total > 0,
                                onTap: () {
                                  controller.previous();
                                  _navigateCurrent();
                                },
                              ),
                              TpIconButton(
                                icon: Icons.keyboard_arrow_down,
                                size: TpIconButton.kCompactSize,
                                compact: true,
                                color: cs.onSurfaceVariant,
                                tooltip: l10n.chatFindNext,
                                enabled: total > 0,
                                onTap: () {
                                  controller.next();
                                  _navigateCurrent();
                                },
                              ),
                              TpIconButton(
                                icon: Icons.close,
                                size: TpIconButton.kCompactSize,
                                compact: true,
                                color: cs.onSurfaceVariant,
                                tooltip: l10n.chatFindClose,
                                onTap: widget.onClose,
                              ),
                            ],
                          ),
                        ),
                        if (hasQuery)
                          total > 0
                              ? _ResultsList(
                                  hits: controller.hits,
                                  currentIndex: current,
                                  query: controller.query,
                                  onTap: _navigateIndex,
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    l10n.chatFindNoResults,
                                    style: TpTextStyles.of(
                                      context,
                                    ).smColored(cs.onSurfaceVariant),
                                  ),
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

  Widget _input(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 220,
      height: _rowHeight,
      child: TextField(
        controller: widget.queryController,
        focusNode: widget.focusNode,
        maxLines: 1,
        autofocus: true,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: context.l10n.chatFindHint,
          hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          filled: true,
          fillColor: cs.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: cs.primary),
          ),
          suffixIcon: widget.queryController.text.isNotEmpty
              ? TpIconButton(
                  icon: Icons.clear,
                  compact: true,
                  size: TpIconButton.kCompactSize,
                  onTap: () {
                    widget.queryController.clear();
                    widget.controller.clear();
                  },
                )
              : null,
        ),
        onChanged: _onChanged,
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
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: hits.length,
        itemBuilder: (context, index) {
          final hit = hits[index];
          final selected = index == currentIndex;
          return Material(
            color: selected
                ? cs.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            child: InkWell(
              onTap: () => onTap(index),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 14,
                      color: cs.onSurfaceVariant,
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
              ),
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
    final cs = Theme.of(context).colorScheme;
    final style = TpTextStyles.of(context).smColored(cs.onSurfaceVariant);
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
              color: cs.primary,
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
