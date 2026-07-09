import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import 'terminal_history_scrollbar.dart';

/// [TerminalView] host chrome: terminal + VTE-style history scrollbar.
class TerminalWithHistoryScrollbar extends StatelessWidget {
  const TerminalWithHistoryScrollbar({
    required this.engine,
    required this.controller,
    required this.child,
    super.key,
  });

  final TerminalEngine engine;
  final TerminalController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: child),
        ListenableBuilder(
          listenable: engine.grid,
          builder: (context, _) => TerminalHistoryScrollbar(
            engine: engine,
            controller: controller,
          ),
        ),
      ],
    );
  }
}
