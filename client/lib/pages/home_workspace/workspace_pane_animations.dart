import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'home_workspace_global_section.dart';
import 'home_workspace_library_view.dart';

/// Which right-hand workspace-home pane is active.
enum WorkspaceRightPaneKind {
  allWorkspaces,
  global,
  library,
  personal,
  team,
}

/// Stable identity for [AnimatedSwitcher] and transition selection.
class WorkspaceRightPaneDescriptor {
  const WorkspaceRightPaneDescriptor._({
    required this.kind,
    this.identityId,
    this.globalView,
    this.libraryView,
  });

  final WorkspaceRightPaneKind kind;
  final String? identityId;
  final HomeGlobalView? globalView;
  final HomeLibraryView? libraryView;

  const WorkspaceRightPaneDescriptor.allWorkspaces()
    : this._(kind: WorkspaceRightPaneKind.allWorkspaces);

  const WorkspaceRightPaneDescriptor.global(HomeGlobalView view)
    : this._(kind: WorkspaceRightPaneKind.global, globalView: view);

  const WorkspaceRightPaneDescriptor.library(HomeLibraryView view)
    : this._(kind: WorkspaceRightPaneKind.library, libraryView: view);

  const WorkspaceRightPaneDescriptor.personal(String profileId)
    : this._(kind: WorkspaceRightPaneKind.personal, identityId: profileId);

  const WorkspaceRightPaneDescriptor.team(String teamId)
    : this._(kind: WorkspaceRightPaneKind.team, identityId: teamId);

  String get switchKey => switch (kind) {
    WorkspaceRightPaneKind.allWorkspaces => 'all-workspaces',
    WorkspaceRightPaneKind.global => 'global-${globalView!.name}',
    WorkspaceRightPaneKind.library => 'library-${libraryView!.name}',
    WorkspaceRightPaneKind.personal => 'personal-$identityId',
    WorkspaceRightPaneKind.team => 'team-$identityId',
  };

  @override
  bool operator ==(Object other) {
    return other is WorkspaceRightPaneDescriptor && switchKey == other.switchKey;
  }

  @override
  int get hashCode => switchKey.hashCode;
}

/// Shared entry motion for workspace-home chrome and data regions.
abstract final class WorkspacePaneAnimations {
  WorkspacePaneAnimations._();

  static const fadeDuration = Duration(milliseconds: 180);
  static const slideDuration = Duration(milliseconds: 220);
  static const crossfadeDuration = Duration(milliseconds: 120);

  /// Full fade + slide when the pane *family* changes (team ↔ global, etc.).
  static bool isStructuralTransition(
    WorkspaceRightPaneDescriptor? from,
    WorkspaceRightPaneDescriptor to,
  ) {
    if (from == null) return false;
    return from.kind != to.kind;
  }

  /// Same pane family, different identity (team A ↔ team B, personal A ↔ B).
  static bool isIdentityTransition(
    WorkspaceRightPaneDescriptor? from,
    WorkspaceRightPaneDescriptor to,
  ) {
    if (from == null) return false;
    if (from.kind != to.kind) return false;
    return from.identityId != to.identityId;
  }

  static Widget switcher({
    required BuildContext context,
    required WorkspaceRightPaneDescriptor descriptor,
    required WorkspaceRightPaneDescriptor? previous,
    required Widget child,
  }) {
    final switching = previous != null && previous != descriptor;
    if (!switching) return child;

    final structural = isStructuralTransition(previous, descriptor);
    final identity = isIdentityTransition(previous, descriptor);
    final disabled = MediaQuery.disableAnimationsOf(context);
    final duration = disabled
        ? Duration.zero
        : (structural || identity ? slideDuration : crossfadeDuration);

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, _) => current!,
      transitionBuilder: structural || identity
          ? _structuralTransition
          : _fadeTransition,
      child: KeyedSubtree(
        key: ValueKey(descriptor.switchKey),
        child: child,
      ),
    );
  }

  static Widget _fadeTransition(Widget child, Animation<double> animation) {
    return FadeTransition(opacity: animation, child: child);
  }

  static Widget _structuralTransition(
    Widget child,
    Animation<double> animation,
  ) {
    final slide = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(slide),
        child: child,
      ),
    );
  }

  static Animate chrome(Widget child, {required Key key}) {
    return child
        .animate(key: key)
        .fadeIn(duration: fadeDuration, curve: Curves.easeOut)
        .slideX(
          begin: 0.025,
          end: 0,
          duration: slideDuration,
          curve: Curves.easeOutCubic,
        );
  }

  static Animate data(Widget child, {required Key key}) {
    return child
        .animate(key: key)
        .fadeIn(duration: fadeDuration, curve: Curves.easeOut)
        .slideX(
          begin: 0.025,
          end: 0,
          duration: slideDuration,
          curve: Curves.easeOutCubic,
        );
  }
}
