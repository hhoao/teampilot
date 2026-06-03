import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

/// Inline find bar for [TerminalView] scrollback search.
class TerminalFindBar extends StatefulWidget {
  const TerminalFindBar({
    required this.engine,
    required this.controller,
    required this.onClose,
    this.searchLabel = 'Find',
    this.noResultsLabel = 'No results',
    super.key,
  });

  final TerminalEngine engine;
  final TerminalController controller;
  final VoidCallback onClose;
  final String searchLabel;
  final String noResultsLabel;

  @override
  State<TerminalFindBar> createState() => _TerminalFindBarState();
}

class _TerminalFindBarState extends State<TerminalFindBar> {
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _runSearch() {
    final query = _queryController.text;
    if (query.isEmpty) {
      widget.controller.searchClear();
      setState(() {});
      return;
    }
    widget.controller.searchSet(query);
    setState(() {});
  }

  void _step(bool forward) {
    if (_queryController.text.isEmpty) return;
    if (forward) {
      widget.controller.searchNext();
    } else {
      widget.controller.searchPrev();
    }
    setState(() {});
  }

  void _close() {
    widget.controller.searchClear();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _queryController.text;
    final status = !widget.controller.searchValid && query.isNotEmpty
        ? widget.noResultsLabel
        : query.isEmpty
        ? ''
        : 'regex';

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
              icon: const Icon(Icons.keyboard_arrow_up, size: AppIconSizes.md),
              onPressed: () => _step(false),
            ),
            IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.keyboard_arrow_down, size: AppIconSizes.md),
              onPressed: () => _step(true),
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close, size: AppIconSizes.md),
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
