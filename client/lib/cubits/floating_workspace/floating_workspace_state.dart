import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../models/floating_workspace_tab.dart';
import '../../services/floating_workspace/floating_workspace_toggle_metrics.dart';

import 'floating_panel_placement.dart';
import 'floating_panel_visibility.dart';

export '../../models/floating_workspace_tab.dart';
export 'floating_panel_placement.dart';

/// Panel chrome snapshot — visibility / geometry / attention.
///
/// Floating tab presence / order / active are owned by
/// [WorkbenchCubit.bar(workspaceId).floating] — see `WorkbenchCubit`. The
/// panel resolves `FloatingTab` view data from the bar by id.
class FloatingWorkspaceState extends Equatable {
  const FloatingWorkspaceState({
    this.visibility = FloatingPanelVisibility.hidden,
    this.isMaximized = false,
    this.activeWorkspaceId = '',
    this.panelPlacement,
    this.legacyAbsoluteBounds,
    this.toggleOffset = kFloatingWorkspaceToggleDefaultOffset,
    this.attention = false,
  });

  final FloatingPanelVisibility visibility;
  final bool isMaximized;
  final String activeWorkspaceId;

  /// App-relative placement (bottom-right insets). Null until first place.
  final FloatingPanelPlacement? panelPlacement;

  /// Prefs written before inset anchoring; converted on first host layout.
  final Rect? legacyAbsoluteBounds;

  final Offset toggleOffset;
  final bool attention;

  bool get hasPlacedPanel =>
      panelPlacement != null || legacyAbsoluteBounds != null;

  FloatingWorkspaceState copyWith({
    FloatingPanelVisibility? visibility,
    bool? isMaximized,
    String? activeWorkspaceId,
    FloatingPanelPlacement? panelPlacement,
    Rect? legacyAbsoluteBounds,
    bool clearPanelPlacement = false,
    bool clearLegacyAbsoluteBounds = false,
    Offset? toggleOffset,
    bool? attention,
  }) {
    return FloatingWorkspaceState(
      visibility: visibility ?? this.visibility,
      isMaximized: isMaximized ?? this.isMaximized,
      activeWorkspaceId: activeWorkspaceId ?? this.activeWorkspaceId,
      panelPlacement: clearPanelPlacement
          ? null
          : (panelPlacement ?? this.panelPlacement),
      legacyAbsoluteBounds: clearLegacyAbsoluteBounds
          ? null
          : (legacyAbsoluteBounds ?? this.legacyAbsoluteBounds),
      toggleOffset: toggleOffset ?? this.toggleOffset,
      attention: attention ?? this.attention,
    );
  }

  @override
  List<Object?> get props => [
    visibility,
    isMaximized,
    activeWorkspaceId,
    panelPlacement,
    legacyAbsoluteBounds,
    toggleOffset,
    attention,
  ];
}
