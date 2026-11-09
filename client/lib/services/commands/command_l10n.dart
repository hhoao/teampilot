import '../../l10n/app_localizations.dart';
import 'command_catalog.dart';
import 'command_definition.dart';

/// Display title for [commandId], resolved via the catalog's
/// `titleL10nKey` into the matching generated [AppLocalizations] getter.
///
/// Returns [commandId] unchanged if it is not in [CommandCatalog.v1] or has
/// no matching l10n key (should not happen for catalog commands; guards
/// against a future catalog/ARB drift crashing the settings UI).
String titleForCommand(AppLocalizations l10n, String commandId) {
  for (final def in CommandCatalog.v1) {
    if (def.id == commandId) {
      if (def.titleL10nKey == 'shortcutsStripFocusTab') {
        final ordinal = _ordinalSuffix(commandId, 'workbench.strip.focusTab');
        if (ordinal != null) {
          return l10n.shortcuts.stripFocusTab(n: ordinal);
        }
      }
      if (def.titleL10nKey == 'shortcutsWorkspaceFocusTab') {
        final ordinal = _ordinalSuffix(
          commandId,
          'workbench.workspace.focusTab',
        );
        if (ordinal != null) {
          return l10n.shortcuts.workspaceFocusTab(n: ordinal);
        }
      }
      return _titleForKey(l10n, def.titleL10nKey) ?? commandId;
    }
  }
  return commandId;
}

/// Parses a `N` suffix after [prefix] (`…focusTabN`), or null if [commandId]
/// is not an ordinal-command id.
int? _ordinalSuffix(String commandId, String prefix) {
  if (!commandId.startsWith(prefix)) return null;
  return int.tryParse(commandId.substring(prefix.length));
}

/// Display name for a [CommandCategory] settings group.
String titleForCategory(AppLocalizations l10n, CommandCategory category) {
  return switch (category) {
    CommandCategory.navigation => l10n.shortcuts.categoryNavigation,
    CommandCategory.tabs => l10n.shortcuts.categoryTabs,
    CommandCategory.view => l10n.shortcuts.categoryView,
    CommandCategory.zoom => l10n.shortcuts.categoryZoom,
    CommandCategory.compose => l10n.shortcuts.categoryCompose,
    CommandCategory.run => l10n.shortcuts.categoryRun,
    CommandCategory.meta => l10n.shortcuts.categoryMeta,
  };
}

String? _titleForKey(AppLocalizations l10n, String titleL10nKey) {
  return switch (titleL10nKey) {
    'shortcutsWorkspaceNextTab' => l10n.shortcuts.workspaceNextTab,
    'shortcutsWorkspacePrevTab' => l10n.shortcuts.workspacePrevTab,
    'shortcutsWorkspaceCloseTab' => l10n.shortcuts.workspaceCloseTab,
    'shortcutsWorkspaceReopenClosed' => l10n.shortcuts.workspaceReopenClosed,
    'shortcutsWorkspaceSearch' => l10n.shortcuts.workspaceSearch,
    'shortcutsWorkspaceContentSearch' => l10n.shortcuts.workspaceContentSearch,
    'shortcutsStripNextTab' => l10n.shortcuts.stripNextTab,
    'shortcutsStripPrevTab' => l10n.shortcuts.stripPrevTab,
    'shortcutsSessionNewTab' => l10n.shortcuts.sessionNewTab,
    'shortcutsSessionNewChat' => l10n.shortcuts.sessionNewChat,
    'shortcutsSessionCloseTab' => l10n.shortcuts.sessionCloseTab,
    'shortcutsWorkbenchSplitRight' => l10n.shortcuts.workbenchSplitRight,
    'shortcutsWorkbenchSplitDown' => l10n.shortcuts.workbenchSplitDown,
    'shortcutsWorkbenchSplitReset' => l10n.shortcuts.workbenchSplitReset,
    'shortcutsWorkbenchFocusNextGroup' =>
      l10n.shortcuts.workbenchFocusNextGroup,
    'shortcutsWorkbenchMoveTabToNextGroup' =>
      l10n.shortcuts.workbenchMoveTabToNextGroup,
    'shortcutsToggleSidebar' => l10n.shortcuts.toggleSidebar,
    'shortcutsTogglePanel' => l10n.shortcuts.togglePanel,
    'shortcutsToggleSecondarySidebar' => l10n.shortcuts.toggleSecondarySidebar,
    'shortcutsFloatingToggle' => l10n.shortcuts.floatingToggle,
    'shortcutsFloatingMaximize' => l10n.shortcuts.floatingMaximize,
    'shortcutsFloatingMinimize' => l10n.shortcuts.floatingMinimize,
    'shortcutsFloatingNewTerminal' => l10n.shortcuts.floatingNewTerminal,
    'shortcutsFloatingOpenFile' => l10n.shortcuts.floatingOpenFile,
    'shortcutsZoomIn' => l10n.shortcuts.zoomIn,
    'shortcutsZoomOut' => l10n.shortcuts.zoomOut,
    'shortcutsZoomReset' => l10n.shortcuts.zoomReset,
    'shortcutsComposeSubmit' => l10n.shortcuts.composeSubmit,
    'shortcutsComposeNewline' => l10n.shortcuts.composeNewline,
    'shortcutsShowCheatsheet' => l10n.shortcuts.showCheatsheet,
    'shortcutsRunSelected' => l10n.shortcuts.runSelected,
    'shortcutsRunStop' => l10n.shortcuts.runStop,
    'shortcutsRunRestart' => l10n.shortcuts.runRestart,
    _ => null,
  };
}
