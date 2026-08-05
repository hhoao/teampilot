import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/services/floating_workspace/floating_workspace_toggle_metrics.dart';

import 'floating_panel_placement.dart';
import 'floating_panel_visibility.dart';

export 'package:teampilot/models/floating_workspace_tab.dart';
export 'floating_panel_placement.dart';

class FloatingWorkspaceBucket extends Equatable {
  const FloatingWorkspaceBucket({
    this.tabs = const [],
    this.activeTabId,
  });

  final List<FloatingTab> tabs;
  final String? activeTabId;

  FloatingWorkspaceBucket copyWith({
    List<FloatingTab>? tabs,
    String? activeTabId,
    bool clearActiveTabId = false,
  }) {
    return FloatingWorkspaceBucket(
      tabs: tabs ?? this.tabs,
      activeTabId: clearActiveTabId ? null : (activeTabId ?? this.activeTabId),
    );
  }

  @override
  List<Object?> get props => [tabs, activeTabId];
}

/// Panel chrome snapshot — visibility / geometry / attention.
///
/// Floating tab buckets live on [FloatingWorkspaceCubit] (see `buckets` /
/// `tabsChanged`), not in this state: tab mutations must not `emit` (every
/// emit wakes every `context.select` / `BlocBuilder` dependent app-wide via
/// BlocProvider). Consumers read tabs through `cubit.bucketFor` /
/// `cubit.activeTabFor` and subscribe to [FloatingWorkspaceCubit.tabsChanged].
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
