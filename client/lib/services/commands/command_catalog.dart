import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/key_chord.dart';

/// Built-in command catalog for keyboard shortcuts.
abstract final class CommandCatalog {
  static final List<CommandDefinition> v1 = [
    // Workspace tabs
    CommandDefinition(
      id: CommandIds.workspaceNextTab,
      category: CommandCategory.navigation,
      defaultChords: [
        KeyChord(
          key: 'arrowRight',
          mods: [KeyChordMod.mod, KeyChordMod.alt],
        ),
      ],
      when: ShortcutWhen.hasOpenWorkspaceTabs,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsWorkspaceNextTab',
    ),
    CommandDefinition(
      id: CommandIds.workspacePrevTab,
      category: CommandCategory.navigation,
      defaultChords: [
        KeyChord(
          key: 'arrowLeft',
          mods: [KeyChordMod.mod, KeyChordMod.alt],
        ),
      ],
      when: ShortcutWhen.hasOpenWorkspaceTabs,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsWorkspacePrevTab',
    ),
    CommandDefinition(
      id: CommandIds.workspaceCloseTab,
      category: CommandCategory.navigation,
      defaultChords: [
        KeyChord(
          key: 'w',
          mods: [KeyChordMod.mod, KeyChordMod.shift],
        ),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsWorkspaceCloseTab',
    ),
    CommandDefinition(
      id: CommandIds.workspaceReopenClosed,
      category: CommandCategory.navigation,
      defaultChords: [
        KeyChord(
          key: 't',
          mods: [KeyChordMod.mod, KeyChordMod.shift],
        ),
      ],
      when: ShortcutWhen.always,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsWorkspaceReopenClosed',
    ),
    CommandDefinition(
      id: CommandIds.workspaceSearch,
      category: CommandCategory.navigation,
      defaultChords: [
        KeyChord(key: 'f', mods: [KeyChordMod.mod]),
        KeyChord.doubleTapShift(),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsWorkspaceSearch',
    ),

    // Session tabs
    CommandDefinition(
      id: CommandIds.sessionNextTab,
      category: CommandCategory.tabs,
      defaultChords: [
        KeyChord(key: 'tab', mods: [KeyChordMod.ctrl]),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsSessionNextTab',
    ),
    CommandDefinition(
      id: CommandIds.sessionPrevTab,
      category: CommandCategory.tabs,
      defaultChords: [
        KeyChord(
          key: 'tab',
          mods: [KeyChordMod.ctrl, KeyChordMod.shift],
        ),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsSessionPrevTab',
    ),
    CommandDefinition(
      id: CommandIds.sessionNewTab,
      category: CommandCategory.tabs,
      defaultChords: [
        KeyChord(key: 't', mods: [KeyChordMod.mod]),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsSessionNewTab',
    ),
    CommandDefinition(
      id: CommandIds.sessionCloseTab,
      category: CommandCategory.tabs,
      defaultChords: [
        KeyChord(key: 'w', mods: [KeyChordMod.mod]),
      ],
      when: ShortcutWhen.hasSessionTab,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsSessionCloseTab',
    ),
    // Alt+1…9 → tabs 1–9; Alt+0 → tab 10.
    for (var n = 1; n <= 10; n++)
      CommandDefinition(
        id: CommandIds.sessionFocusTab(n),
        category: CommandCategory.tabs,
        defaultChords: [
          KeyChord(
            key: n == 10 ? 'digit0' : 'digit$n',
            mods: [KeyChordMod.alt],
          ),
        ],
        when: ShortcutWhen.hasWorkspace,
        terminalPassthrough: true,
        // Resolved with ordinal in [titleForCommand].
        titleL10nKey: 'shortcutsSessionFocusTab',
      ),

    // View
    CommandDefinition(
      id: CommandIds.toggleSidebar,
      category: CommandCategory.view,
      defaultChords: [
        KeyChord(key: 'b', mods: [KeyChordMod.mod]),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsToggleSidebar',
    ),
    CommandDefinition(
      id: CommandIds.togglePanel,
      category: CommandCategory.view,
      defaultChords: [
        KeyChord(key: 'j', mods: [KeyChordMod.mod]),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsTogglePanel',
    ),
    CommandDefinition(
      id: CommandIds.toggleSecondarySidebar,
      category: CommandCategory.view,
      defaultChords: [
        KeyChord(
          key: 'b',
          mods: [KeyChordMod.mod, KeyChordMod.alt],
        ),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsToggleSecondarySidebar',
    ),

    // Zoom
    CommandDefinition(
      id: CommandIds.zoomIn,
      category: CommandCategory.zoom,
      defaultChords: [
        KeyChord(key: 'equal', mods: [KeyChordMod.mod]),
        KeyChord(key: 'numpadAdd', mods: [KeyChordMod.mod]),
      ],
      when: ShortcutWhen.always,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsZoomIn',
    ),
    CommandDefinition(
      id: CommandIds.zoomOut,
      category: CommandCategory.zoom,
      defaultChords: [
        KeyChord(key: 'minus', mods: [KeyChordMod.mod]),
        KeyChord(key: 'numpadSubtract', mods: [KeyChordMod.mod]),
      ],
      when: ShortcutWhen.always,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsZoomOut',
    ),
    CommandDefinition(
      id: CommandIds.zoomReset,
      category: CommandCategory.zoom,
      defaultChords: [
        KeyChord(key: 'digit0', mods: [KeyChordMod.mod]),
      ],
      when: ShortcutWhen.always,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsZoomReset',
    ),

    // Compose
    CommandDefinition(
      id: CommandIds.composeSubmit,
      category: CommandCategory.compose,
      defaultChords: [
        KeyChord(key: 'enter'),
      ],
      when: ShortcutWhen.inCompose,
      terminalPassthrough: false,
      titleL10nKey: 'shortcutsComposeSubmit',
    ),
    CommandDefinition(
      id: CommandIds.composeNewline,
      category: CommandCategory.compose,
      defaultChords: [
        KeyChord(key: 'enter', mods: [KeyChordMod.mod]),
      ],
      when: ShortcutWhen.inCompose,
      terminalPassthrough: false,
      titleL10nKey: 'shortcutsComposeNewline',
    ),

    // Run (VS Code-shaped: F5 / Shift+F5 / Mod+Shift+F5)
    CommandDefinition(
      id: CommandIds.runRunSelected,
      category: CommandCategory.run,
      defaultChords: [
        KeyChord(key: 'f5'),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsRunSelected',
    ),
    CommandDefinition(
      id: CommandIds.runStop,
      category: CommandCategory.run,
      defaultChords: [
        KeyChord(key: 'f5', mods: [KeyChordMod.shift]),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsRunStop',
    ),
    CommandDefinition(
      id: CommandIds.runRestart,
      category: CommandCategory.run,
      defaultChords: [
        KeyChord(
          key: 'f5',
          mods: [KeyChordMod.mod, KeyChordMod.shift],
        ),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsRunRestart',
    ),

    // Meta
    CommandDefinition(
      id: CommandIds.showCheatsheet,
      category: CommandCategory.meta,
      defaultChords: [
        KeyChord(key: 'slash', mods: [KeyChordMod.mod]),
      ],
      when: ShortcutWhen.always,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsShowCheatsheet',
    ),
  ];
}
