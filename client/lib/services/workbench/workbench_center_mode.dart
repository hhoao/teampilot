import '../commands/command_ids.dart';

enum WorkbenchCenterMode { compose, welcome, tab }

/// Single source of truth for workspace center chrome/body.
WorkbenchCenterMode resolveWorkbenchCenterMode({
  required bool newChatActive,
  required Object? activeTabId,
}) {
  if (newChatActive) return WorkbenchCenterMode.compose;
  if (activeTabId == null) return WorkbenchCenterMode.welcome;
  return WorkbenchCenterMode.tab;
}

/// Fixed welcome shortcut rows (labels via [titleForCommand]).
const List<String> kWorkbenchWelcomeCommandIds = [
  CommandIds.sessionNewTab,
  CommandIds.togglePanel,
  CommandIds.toggleSidebar,
  CommandIds.workspaceSearch,
  CommandIds.showCheatsheet,
];
