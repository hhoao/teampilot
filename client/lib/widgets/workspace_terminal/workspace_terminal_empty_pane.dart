import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// Empty Terminal tab body: prompt to create a session (no PTY until then).
///
/// Layout mirrors Orca's floating launcher row: leading terminal icon inline
/// with the action label (not stacked above it).
class WorkspaceTerminalEmptyPane extends StatelessWidget {
  const WorkspaceTerminalEmptyPane({
    required this.onNewTerminal,
    required this.foreground,
    super.key,
  });

  final VoidCallback onNewTerminal;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onNewTerminal,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal_outlined, size: 20, color: foreground),
                const SizedBox(width: 12),
                Text(
                  l10n.workspaceTerminalNewSession,
                  style: styles.smMediumColored(foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
