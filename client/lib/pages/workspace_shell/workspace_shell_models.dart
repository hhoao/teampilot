import 'package:flutter/material.dart';

import '../../cubits/workbench/workbench_tab.dart';
import '../../models/team_config.dart';

enum AppSection { chat, runs, config }

class TabInfo {
  const TabInfo({
    required this.id,
    required this.title,
    this.sessionId,
    this.working = false,
    this.icon = Icons.terminal_rounded,
    this.cli,
    this.accentColor,
    this.preview = false,
    this.pinnable = false,
    this.pinned = false,
    this.kind,
    this.filePath,
  });

  final String id;
  final String title;

  /// Center-strip tab kind for context menu composition.
  final WorkbenchTabKind? kind;

  /// Absolute file path for file/diff tabs.
  final String? filePath;

  /// When set, tab chip live-selects working + title from [ChatCubit].
  final String? sessionId;

  /// Session has a member in a turn → show the working spinner left of title.
  final bool working;

  /// Icon shown left of the title, after the accent bar.
  /// Defaults to [Icons.terminal_rounded].
  final IconData icon;

  /// When set, renders [CliBrandIcon] instead of [icon].
  final CliTool? cli;

  /// Color of the 3px left accent bar. When null, falls back to
  /// [ColorScheme.primary].
  final Color? accentColor;

  /// Preview (replaceable) editor/diff tab — rendered italic like VS Code/Orca.
  final bool preview;

  /// Session tabs can pin; file/diff tabs cannot.
  final bool pinnable;

  /// [AppSession.pinned] for session tabs — sidebar sort only.
  final bool pinned;
}
