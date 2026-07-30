import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'floating_panel_visibility.dart';

class FloatingTab extends Equatable {
  const FloatingTab({
    required this.id,
    required this.surfaceId,
    required this.title,
    this.payload,
  });

  final String id;
  final String surfaceId;
  final String title;
  final Object? payload;

  FloatingTab copyWith({
    String? id,
    String? surfaceId,
    String? title,
    Object? payload,
  }) {
    return FloatingTab(
      id: id ?? this.id,
      surfaceId: surfaceId ?? this.surfaceId,
      title: title ?? this.title,
      payload: payload ?? this.payload,
    );
  }

  @override
  List<Object?> get props => [id, surfaceId, title, payload];
}

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

class FloatingWorkspaceState extends Equatable {
  const FloatingWorkspaceState({
    this.visibility = FloatingPanelVisibility.hidden,
    this.isMaximized = false,
    this.activeWorkspaceId = '',
    this.buckets = const {},
    this.panelBounds = const Rect.fromLTWH(80, 80, 720, 480),
    this.toggleOffset = const Offset(-24, -24),
    this.attention = false,
  });

  final FloatingPanelVisibility visibility;
  final bool isMaximized;
  final String activeWorkspaceId;
  final Map<String, FloatingWorkspaceBucket> buckets;
  final Rect panelBounds;
  final Offset toggleOffset;
  final bool attention;

  FloatingWorkspaceBucket get activeBucket =>
      buckets[activeWorkspaceId] ?? const FloatingWorkspaceBucket();

  FloatingWorkspaceState copyWith({
    FloatingPanelVisibility? visibility,
    bool? isMaximized,
    String? activeWorkspaceId,
    Map<String, FloatingWorkspaceBucket>? buckets,
    Rect? panelBounds,
    Offset? toggleOffset,
    bool? attention,
  }) {
    return FloatingWorkspaceState(
      visibility: visibility ?? this.visibility,
      isMaximized: isMaximized ?? this.isMaximized,
      activeWorkspaceId: activeWorkspaceId ?? this.activeWorkspaceId,
      buckets: buckets ?? this.buckets,
      panelBounds: panelBounds ?? this.panelBounds,
      toggleOffset: toggleOffset ?? this.toggleOffset,
      attention: attention ?? this.attention,
    );
  }

  @override
  List<Object?> get props => [
    visibility,
    isMaximized,
    activeWorkspaceId,
    buckets,
    panelBounds,
    toggleOffset,
    attention,
  ];
}
