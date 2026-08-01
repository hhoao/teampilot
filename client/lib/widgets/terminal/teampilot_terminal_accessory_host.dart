import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

/// Chrome that optionally stacks a touch [TerminalAccessoryBar] below [child].
///
/// Extracted for testability — [TeampilotAlacrittyTerminal] uses this on
/// Android/iOS; desktop keeps [child] only.
class TeampilotTerminalAccessoryHost extends StatefulWidget {
  const TeampilotTerminalAccessoryHost({
    required this.child,
    required this.viewKey,
    required this.latch,
    this.showAccessory = true,
    super.key,
  });

  final Widget child;
  final GlobalKey<TerminalViewState> viewKey;
  final ModifierLatch latch;
  final bool showAccessory;

  @override
  State<TeampilotTerminalAccessoryHost> createState() =>
      _TeampilotTerminalAccessoryHostState();
}

class _TeampilotTerminalAccessoryHostState
    extends State<TeampilotTerminalAccessoryHost> {
  var _imeShown = true;

  void _onBeforeKey() {
    final view = widget.viewKey.currentState;
    view?.requestTerminalFocus();
    view?.ensureKeyboardVisible();
  }

  void _onInjectKey(LogicalKeyboardKey key) {
    widget.viewKey.currentState?.injectLogicalKey(key);
  }

  void _onToggleIme() {
    if (_imeShown) {
      widget.viewKey.currentState?.hideKeyboard();
      _imeShown = false;
    } else {
      widget.viewKey.currentState?.ensureKeyboardVisible();
      _imeShown = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showAccessory) {
      return widget.child;
    }

    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(child: widget.child),
        Material(
          color: theme.colorScheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            child: TerminalAccessoryBar(
              layout: TerminalAccessoryLayout.serverBoxDualRow,
              latch: widget.latch,
              onBeforeKey: _onBeforeKey,
              onInjectKey: _onInjectKey,
              onToggleIme: _onToggleIme,
            ),
          ),
        ),
      ],
    );
  }
}
