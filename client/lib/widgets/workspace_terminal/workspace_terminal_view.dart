import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/editor_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../services/terminal/terminal_fonts.dart';
import '../../services/terminal/terminal_uri_opener.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../services/terminal/workspace_terminal_title_resolver.dart';

class WorkspaceTerminalView extends StatelessWidget {
  const WorkspaceTerminalView({
    required this.entry,
    required this.theme,
    required this.terminalViewKey,
    required this.siblings,
    required this.onContextMenu,
    super.key,
  });

  final WorkspaceTerminalEntry entry;
  final TerminalTheme theme;
  final GlobalKey<TerminalViewState> terminalViewKey;
  final List<WorkspaceTerminalEntry> siblings;
  final void Function(Offset globalPosition, CellOffset? cell) onContextMenu;

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
        child: TerminalView(
          entry.session.engine,
          key: terminalViewKey,
          controller: entry.controller,
          theme: theme,
          backgroundOpacity: 0.98,
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 8),
          textStyle: appTerminalTextStyle(context),
          autofocus: true,
          linkProviders: entry.session.linkProviders,
          primaryTapActivatesLink: context
              .watch<SessionPreferencesCubit>()
              .state
              .preferences
              .terminalLinkClickOpensInApp,
          onPtyResize: entry.session.onTerminalPtyResize,
          onLinkActivate: (uri) {
            final editorCubit = context.read<EditorCubit>();
            unawaited(
              TerminalUriOpener.open(
                uri,
                workingDirectory: entry.cwd,
                openInEditor: (path) => editorCubit.openFile(path),
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
