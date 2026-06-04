import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/input/paste.dart' as alacritty_paste;
import 'package:flutter_alacritty/input/term_mode.dart' show anyMouse;

import '../../l10n/l10n_extensions.dart';
import '../../services/terminal/terminal_export.dart';
import '../../widgets/menu/sidebar_action_menu.dart';

/// Right-click menu for the chat workbench terminal surface.
Future<void> showChatWorkbenchTerminalContextMenu({
  required BuildContext context,
  required BuildContext menuContext,
  required TerminalController terminalController,
  required Offset globalPosition,
  required TerminalEngine engine,
  required CellOffset? cellOffset,
  required bool sessionRunning,
  required VoidCallback onFindRequested,
  required Future<void> Function(String link) onOpenLink,
  required Future<void> Function() onExportScrollback,
  required VoidCallback onDisconnect,
  required Future<void> Function() onRestart,
}) async {
  final mloc = MaterialLocalizations.of(menuContext);
  final hasSelection = terminalController.selectionActive;
  final mouseReporting = anyMouse(engine.grid.modeFlags);
  final linkUri = cellOffset != null
      ? engine.hyperlinkAt(cellOffset.row, cellOffset.column)
      : null;
  final specs = <SidebarActionMenuSpec>[
    SidebarActionMenuSpec.item(
      value: 'find',
      icon: Icons.search,
      label: context.l10n.terminalFind,
    ),
    if (linkUri != null)
      SidebarActionMenuSpec.item(
        value: 'openLink',
        icon: Icons.link,
        label: context.l10n.terminalOpenLink,
      ),
    SidebarActionMenuSpec.item(
      value: 'export',
      icon: Icons.download_outlined,
      label: context.l10n.terminalExportScrollback,
    ),
    const SidebarActionMenuSpec.divider(),
    SidebarActionMenuSpec.item(
      value: 'paste',
      icon: Icons.content_paste,
      label: mloc.pasteButtonLabel,
    ),
    SidebarActionMenuSpec.item(
      value: 'copy',
      icon: Icons.content_copy,
      label: (!hasSelection && mouseReporting)
          ? menuContext.l10n.terminalCopySelectHint
          : mloc.copyButtonLabel,
      enabled: hasSelection,
    ),
    SidebarActionMenuSpec.item(
      value: 'selectAll',
      icon: Icons.select_all,
      label: mloc.selectAllButtonLabel,
    ),
    SidebarActionMenuSpec.item(
      value: 'clearSelection',
      icon: Icons.deselect,
      label: 'Clear selection',
    ),
    if (sessionRunning) ...[
      const SidebarActionMenuSpec.divider(),
      const SidebarActionMenuSpec.item(
        value: 'disconnect',
        icon: Icons.link_off,
        label: 'Disconnect',
      ),
      const SidebarActionMenuSpec.item(
        value: 'restart',
        icon: Icons.restart_alt,
        label: 'Restart session',
      ),
    ],
  ];

  final selected = await showSidebarActionMenuFromSpecs<String>(
    context: menuContext,
    globalPosition: globalPosition,
    popUpAnimationStyle: const AnimationStyle(duration: Duration.zero),
    specs: specs,
  );
  if (!menuContext.mounted) return;
  switch (selected) {
    case 'find':
      onFindRequested();
    case 'openLink':
      if (linkUri != null) {
        await onOpenLink(linkUri);
      }
    case 'export':
      await onExportScrollback();
    case 'paste':
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.isNotEmpty) {
        terminalController.onTerminalInputStart();
        engine.write(
          alacritty_paste.pasteBytes(text, modeFlags: engine.grid.modeFlags),
        );
        terminalController.clearSelection();
      }
    case 'copy':
      final text = terminalController.readSelectionText();
      if (text != null && text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
      }
    case 'selectAll':
      final grid = engine.grid;
      if (grid.rows > 0 && grid.columns > 0) {
        terminalController.selectionStart(0, 0, false, 0);
        terminalController.selectionUpdate(
          grid.rows - 1,
          grid.columns - 1,
          false,
        );
      }
    case 'clearSelection':
      terminalController.clearSelection();
    case 'disconnect':
      onDisconnect();
    case 'restart':
      await onRestart();
    default:
      break;
  }
}

Future<void> exportChatWorkbenchTerminalScrollback(
  BuildContext context,
  TerminalEngine engine,
) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: context.l10n.terminalExportScrollback,
    fileName: 'terminal-scrollback.txt',
    type: FileType.custom,
    allowedExtensions: ['txt'],
  );
  if (path == null || !context.mounted) return;
  await File(path).writeAsString(exportTerminalScrollback(engine));
}
