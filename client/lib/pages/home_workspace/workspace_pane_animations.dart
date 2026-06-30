import 'package:flutter/material.dart';

import '../../widgets/deferred_mount_shell.dart';
import '../../widgets/pane_entry_animation.dart';
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

  static const slideDuration = Duration(milliseconds: 220);

  /// Panes that already run their own entry motion — [switcher] must not stack
  /// [AnimatedSwitcher] + deferred mount on top (feels like double animation).
  static bool _paneHandlesOwnEntryMotion(WorkspaceRightPaneKind kind) =>
      switch (kind) {
        WorkspaceRightPaneKind.global ||
        WorkspaceRightPaneKind.team ||
        WorkspaceRightPaneKind.personal ||
        WorkspaceRightPaneKind.allWorkspaces ||
        WorkspaceRightPaneKind.library => true,
      };

  static Widget switcher({
    required BuildContext context,
    required WorkspaceRightPaneDescriptor descriptor,
    required WorkspaceRightPaneDescriptor? previous,
    required Widget child,
  }) {
    final switching = previous != null && previous != descriptor;
    if (!switching) return child;

    if (_paneHandlesOwnEntryMotion(previous.kind) ||
        _paneHandlesOwnEntryMotion(descriptor.kind)) {
      return KeyedSubtree(
        key: ValueKey(descriptor.switchKey),
        child: child,
      );
    }

    final disabled = MediaQuery.disableAnimationsOf(context);
    final duration = disabled ? Duration.zero : slideDuration;

    final paneChild = duration > Duration.zero
        ? DeferredMountAfter(
            delay: duration,
            child: DeferredMountShell(
              delayFrames: 1,
              child: child,
            ),
          )
        : child;

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, _) => current!,
      transitionBuilder: (child, animation) =>
          paneSwitcherStructuralTransition(child, animation, context),
      child: KeyedSubtree(
        key: ValueKey(descriptor.switchKey),
        child: paneChild,
      ),
    );
  }

  static Widget chrome(Widget child, {required Key key}) {
    return PaneEntryAnimation(key: key, child: child);
  }

  static Widget data(Widget child, {required Key key}) {
    return PaneEntryAnimation(key: key, child: child);
  }
}
