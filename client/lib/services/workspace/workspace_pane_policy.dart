import '../../models/layout_preferences.dart';

class WorkspacePaneEffective {
  const WorkspacePaneEffective({
    required this.isNarrow,
    required this.dockLeft,
    required this.dockRight,
    required this.dockBottom,
    required this.overlayLeft,
    required this.overlayRight,
  });

  final bool isNarrow;
  final bool dockLeft;
  final bool dockRight;
  final bool dockBottom;
  final bool overlayLeft;
  final bool overlayRight;
}

abstract final class WorkspacePanePolicy {
  /// Logical px; confirmed in Task 1 spike.
  static const double narrowBreakpointWidth = 840;

  static WorkspacePaneEffective effective({
    required LayoutPreferences preferences,
    required double viewportWidth,
    bool composeLanding = false,
    bool? landingRightToolsOverride,
  }) {
    final rightIntent = composeLanding
        ? (landingRightToolsOverride ?? false)
        : preferences.rightToolsVisible;
    final narrow = viewportWidth < narrowBreakpointWidth;
    if (!narrow) {
      return WorkspacePaneEffective(
        isNarrow: false,
        dockLeft: preferences.sidebarVisible,
        dockRight: rightIntent,
        dockBottom: preferences.workspaceTerminalVisible,
        overlayLeft: false,
        overlayRight: false,
      );
    }
    return WorkspacePaneEffective(
      isNarrow: true,
      dockLeft: false,
      dockRight: false,
      dockBottom: preferences.workspaceTerminalVisible,
      overlayLeft: preferences.sidebarVisible,
      overlayRight: rightIntent,
    );
  }
}
