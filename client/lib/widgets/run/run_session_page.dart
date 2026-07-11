import 'package:flutter/material.dart';

import '../../services/run/run_terminal_bridge.dart';
import '../../theme/workspace_surface_layers.dart';

/// Scrollable text log for one [RunSession] (YAGNI: plain text for all types).
class RunSessionPage extends StatelessWidget {
  const RunSessionPage({
    required this.sessionId,
    required this.bridge,
    super.key,
  });

  final String sessionId;
  final RunTerminalBridge bridge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: bridge,
      builder: (context, _) {
        final text = bridge.textFor(sessionId);
        return ColoredBox(
          color: cs.workspaceCode,
          child: SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  text.isEmpty ? '' : text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.4,
                    color: cs.workspacePrimaryText,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
