import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Inline find bar for [TerminalView] scrollback search.
class TerminalFindBar extends StatefulWidget {
  const TerminalFindBar({
    required this.terminal,
    required this.controller,
    required this.onClose,
    this.searchLabel = 'Find',
    this.noResultsLabel = 'No results',
    super.key,
  });

  final Terminal terminal;
  final TerminalController controller;
  final VoidCallback onClose;
  final String searchLabel;
  final String noResultsLabel;

  @override
  State<TerminalFindBar> createState() => _TerminalFindBarState();
}

class _TerminalFindBarState extends State<TerminalFindBar> {
  final _queryController = TextEditingController();
  var _matchCount = 0;
  var _matchIndex = 0;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _runSearch() {
    final query = _queryController.text;
    if (query.isEmpty) {
      widget.terminal.search.clear();
      widget.controller.clearSearch();
      setState(() {
        _matchCount = 0;
        _matchIndex = 0;
      });
      return;
    }

    final count = widget.terminal.search.find(query);
    widget.controller.setSearchResults(
      widget.terminal.search.hits,
      activeIndex: widget.terminal.search.currentIndex,
    );
    setState(() {
      _matchCount = count;
      _matchIndex = count == 0 ? 0 : widget.terminal.search.currentIndex + 1;
    });
  }

  void _step(bool forward) {
    if (_matchCount == 0) return;
    final hit = forward
        ? widget.terminal.search.next()
        : widget.terminal.search.previous();
    if (hit == null) return;
    widget.controller.setSearchResults(
      widget.terminal.search.hits,
      activeIndex: widget.terminal.search.currentIndex,
    );
    setState(() {
      _matchIndex = widget.terminal.search.currentIndex + 1;
    });
  }

  void _close() {
    widget.terminal.search.clear();
    widget.controller.clearSearch();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = _matchCount == 0 && _queryController.text.isNotEmpty
        ? widget.noResultsLabel
        : _matchCount > 0
        ? '$_matchIndex / $_matchCount'
        : '';

    return Material(
      elevation: 4,
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _queryController,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.searchLabel,
                  border: const OutlineInputBorder(),
                  suffixText: status,
                ),
                onChanged: (_) => _runSearch(),
                onSubmitted: (_) => _step(true),
              ),
            ),
            IconButton(
              tooltip: 'Previous',
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              onPressed: () => _step(false),
            ),
            IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              onPressed: () => _step(true),
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close, size: 20),
              onPressed: _close,
            ),
          ],
        ),
      ),
    );
  }
}

/// Keyboard shortcuts for terminal find (Ctrl+Shift+F, F3, Escape).
class TerminalFindShortcuts extends StatelessWidget {
  const TerminalFindShortcuts({
    required this.child,
    required this.findVisible,
    required this.onToggleFind,
    required this.onFindNext,
    required this.onFindPrevious,
    required this.onCloseFind,
    super.key,
  });

  final Widget child;
  final bool findVisible;
  final VoidCallback onToggleFind;
  final VoidCallback onFindNext;
  final VoidCallback onFindPrevious;
  final VoidCallback onCloseFind;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
            const _TerminalFindToggleIntent(),
        const SingleActivator(LogicalKeyboardKey.f3): const _TerminalFindNextIntent(),
        const SingleActivator(LogicalKeyboardKey.f3, shift: true):
            const _TerminalFindPreviousIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const _TerminalFindCloseIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _TerminalFindToggleIntent: CallbackAction<_TerminalFindToggleIntent>(
            onInvoke: (_) {
              if (findVisible) {
                onCloseFind();
              } else {
                onToggleFind();
              }
              return null;
            },
          ),
          _TerminalFindNextIntent: CallbackAction<_TerminalFindNextIntent>(
            onInvoke: (_) {
              if (findVisible) onFindNext();
              return null;
            },
          ),
          _TerminalFindPreviousIntent: CallbackAction<_TerminalFindPreviousIntent>(
            onInvoke: (_) {
              if (findVisible) onFindPrevious();
              return null;
            },
          ),
          _TerminalFindCloseIntent: CallbackAction<_TerminalFindCloseIntent>(
            onInvoke: (_) {
              if (findVisible) onCloseFind();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

class _TerminalFindToggleIntent extends Intent {
  const _TerminalFindToggleIntent();
}

class _TerminalFindNextIntent extends Intent {
  const _TerminalFindNextIntent();
}

class _TerminalFindPreviousIntent extends Intent {
  const _TerminalFindPreviousIntent();
}

class _TerminalFindCloseIntent extends Intent {
  const _TerminalFindCloseIntent();
}
