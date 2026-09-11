// lib/cubits/workbench/workbench_tab_bar.dart
import 'package:equatable/equatable.dart';

import 'workbench_split_layout.dart';

/// Per-workspace tab state: the center layout (session/file/diff groups) and
/// the floating layout (shell/run/file-preview groups). Both are
/// [WorkbenchGroupLayout]s — each leaf group holds one strip
/// (see `tab_strip.dart`).
///
/// Not const-constructible: the default of each surface is the degenerate
/// single-group layout built by [singleGroupLayout]. [WorkbenchState.bar]
/// therefore serves a cached default instance.
class WorkspaceTabBar extends Equatable {
  WorkspaceTabBar({WorkbenchGroupLayout? center, WorkbenchGroupLayout? floating})
    : center = center ?? singleGroupLayout(),
      floating = floating ?? singleGroupLayout();

  final WorkbenchGroupLayout center;
  final WorkbenchGroupLayout floating;

  WorkspaceTabBar copyWith({
    WorkbenchGroupLayout? center,
    WorkbenchGroupLayout? floating,
  }) => WorkspaceTabBar(
    center: center ?? this.center,
    floating: floating ?? this.floating,
  );

  @override
  List<Object?> get props => [center, floating];
}
