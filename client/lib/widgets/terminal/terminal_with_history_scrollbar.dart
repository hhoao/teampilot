import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import 'terminal_history_scrollbar.dart';

/// [TerminalView] host chrome: terminal + VTE-style history scrollbar.
///
/// The scrollbar listens to [TerminalEngine.repaint] itself and paints the
/// thumb without rebuilding widgets. Do not wrap it in [ListenableBuilder]
/// over [TerminalEngine.grid] — that rebuilds the track on every cell update.
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
        RepaintBoundary(
          child: TerminalHistoryScrollbar(
            engine: engine,
            controller: controller,
          ),
        ),
      ],
    );
  }
}
