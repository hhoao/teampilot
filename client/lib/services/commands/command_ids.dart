/// Stable command identifiers for the v1 keyboard shortcut catalog.
abstract final class CommandIds {
  // Workspace tabs
  static const String workspaceNextTab = 'workbench.workspace.nextTab';
  static const String workspacePrevTab = 'workbench.workspace.prevTab';
  static const String workspaceCloseTab = 'workbench.workspace.closeTab';
  static const String workspaceReopenClosed = 'workbench.workspace.reopenClosed';
  static const String workspaceSearch = 'workbench.workspace.search';

  // Session tabs
  static const String sessionNextTab = 'workbench.session.nextTab';
  static const String sessionPrevTab = 'workbench.session.prevTab';
  static const String sessionNewTab = 'workbench.session.newTab';
  static const String sessionCloseTab = 'workbench.session.closeTab';

  /// 1-based ordinal → `workbench.session.focusTabN` (N = 1…10).
  /// Bound to Alt+1…9 / Alt+0 (10th tab).
  static String sessionFocusTab(int oneBased) {
    assert(oneBased >= 1 && oneBased <= 10);
    return 'workbench.session.focusTab$oneBased';
  }

  /// All [sessionFocusTab] ids in ordinal order (1…10).
  static final List<String> sessionFocusTabs = [
    for (var n = 1; n <= 10; n++) sessionFocusTab(n),
  ];

  // View
  static const String toggleSidebar = 'workbench.view.toggleSidebar';
  static const String togglePanel = 'workbench.view.togglePanel';
  static const String toggleSecondarySidebar =
      'workbench.view.toggleSecondarySidebar';

  // Zoom
  static const String zoomIn = 'workbench.zoom.in';
  static const String zoomOut = 'workbench.zoom.out';
  static const String zoomReset = 'workbench.zoom.reset';

  // Compose
  static const String composeSubmit = 'compose.submit';
  static const String composeNewline = 'compose.newline';

  // Meta
  static const String showCheatsheet = 'workbench.shortcuts.showCheatsheet';

  // Run
  static const String runRunSelected = 'run.runSelected';
  static const String runStop = 'run.stop';
  static const String runRestart = 'run.restart';
}
