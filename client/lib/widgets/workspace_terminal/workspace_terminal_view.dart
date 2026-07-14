import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/terminal/terminal_uri_opener.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../services/terminal/workspace_terminal_title_resolver.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../terminal/teampilot_alacritty_terminal.dart';

class WorkspaceTerminalView extends StatelessWidget {
  const WorkspaceTerminalView({
    required this.entry,
    required this.theme,
    required this.terminalViewKey,
    required this.siblings,
    required this.onContextMenu,
    required this.workspaceId,
    super.key,
  });

  final WorkspaceTerminalEntry entry;
  final TerminalTheme theme;
  final GlobalKey<TerminalViewState> terminalViewKey;
  final List<WorkspaceTerminalEntry> siblings;
  final void Function(Offset globalPosition, CellOffset? cell) onContextMenu;
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final background = Color(0xFF000000 | theme.background);
    final title = WorkspaceTerminalTitleResolver.tabTitle(
      entry: entry,
      siblings: siblings,
      baseLabel: entry.titleLabel.isEmpty ? '…' : entry.titleLabel,
    );
    return ColoredBox(
      color: background,
      child: Semantics(
        label: title,
        child: TeampilotAlacrittyTerminal(
          engine: entry.session.engine,
          controller: entry.controller,
          theme: theme,
          terminalViewKey: terminalViewKey,
          // Dock shell: tighter inset than the chat workbench terminal.
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          linkProviders: entry.session.linkProviders,
          onPtyResize: entry.session.onTerminalPtyResize,
          onLinkActivate: (uri) {
            final opener = context.read<WorkbenchEditorOpener>();
            unawaited(
              TerminalUriOpener.open(
                uri,
                workingDirectory: entry.cwd,
                openInEditor: (path) => opener.openFile(workspaceId, path),
              ),
            );
          },
          onSecondaryTapDown: (details, offset) {
            onContextMenu(details.globalPosition, offset);
          },
        ),
      ),
    );
  }
}
