import 'layout_cubit.dart';

/// Whether the narrow unified workspace drawer should be shown open.
///
/// Matches IdeShell narrow open derivation: left overlay intent (unless
/// suppressed) or effective right-tools visibility.
bool mobileWorkspaceDrawerOpen({
  required LayoutState layoutState,
  required bool composeLanding,
}) {
  final right = composeLanding
      ? (layoutState.landingRightToolsOverride ?? false)
      : layoutState.preferences.rightToolsVisible;
  return (layoutState.preferences.sidebarVisible &&
          !layoutState.narrowLeftSuppressed) ||
      right;
}

/// Drawer body when open: tools if right-tools intent is effective, else chat.
MobileDrawerMode mobileWorkspaceDrawerDisplayMode({
  required bool rightToolsEffective,
}) =>
    rightToolsEffective ? MobileDrawerMode.tools : MobileDrawerMode.chat;
