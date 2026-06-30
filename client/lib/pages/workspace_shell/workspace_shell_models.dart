import 'package:flutter/material.dart';

import '../../models/team_config.dart';

enum AppSection { chat, runs, config }

class TabInfo {
  const TabInfo({
    required this.id,
    required this.title,
    this.working = false,
    this.icon = Icons.terminal_rounded,
    this.cli,
    this.accentColor,
  });

  final String id;
  final String title;

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
}
