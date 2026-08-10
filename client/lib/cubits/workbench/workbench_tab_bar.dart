// lib/cubits/workbench/workbench_tab_bar.dart
import 'package:equatable/equatable.dart';

import 'tab_strip.dart';

/// Per-workspace tab state: the center strip (session/file/diff) and the
/// floating strip (shell/run). Both are [TabStrip]s — one owner each.
class WorkspaceTabBar extends Equatable {
  const WorkspaceTabBar({
    this.center = const TabStrip(),
    this.floating = const TabStrip(),
  });

  final TabStrip center;
  final TabStrip floating;

  WorkspaceTabBar copyWith({TabStrip? center, TabStrip? floating}) =>
      WorkspaceTabBar(
        center: center ?? this.center,
        floating: floating ?? this.floating,
      );

  @override
  List<Object?> get props => [center, floating];
}
