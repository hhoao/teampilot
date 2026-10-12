import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/input/paste.dart' as alacritty_paste;
import 'package:flutter_alacritty/input/term_mode.dart' show anyMouse;
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/selection_ai/selection_ai_context.dart';
import '../../services/selection_ai/selection_ai_menu_specs.dart';

/// Right-click menu for the floating workspace shell terminal.
Future<void> showWorkspaceTerminalContextMenu({
  required BuildContext context,
  required BuildContext menuContext,
  required TerminalController terminalController,
  required TerminalEngine engine,
  required Offset globalPosition,
  required CellOffset? cellOffset,
  required VoidCallback onFindRequested,
  required VoidCallback onClearTerminal,
  required Future<void> Function(String link) onOpenLink,
  required Future<void> Function(String aiContext) onAskAi,
}) async {
  final mloc = MaterialLocalizations.of(menuContext);
  final hasSelection = terminalController.selectionActive;
  final selectionText = terminalController.readSelectionText() ?? '';
  final aiContext = buildTerminalAiContextClipboardText(
    surfaceLabel: 'workspace-shell',
    text: selectionText,
  );
  final hasAi = aiContext.isNotEmpty;
  final mouseReporting = anyMouse(engine.grid.modeFlags);
  final linkUri = cellOffset != null
      ? engine.hyperlinkAt(cellOffset.row, cellOffset.column)
      : null;
  final specs = <TpActionMenuSpec>[
    TpActionMenuSpec.item(
      value: 'find',
      icon: Icons.search,
      label: context.l10n.terminalFind,
    ),
    TpActionMenuSpec.item(
      value: 'clear',
      icon: Icons.cleaning_services_outlined,
      label: context.l10n.terminalClear,
    ),
    if (linkUri != null)
      TpActionMenuSpec.item(
        value: 'openLink',
        icon: Icons.link,
        label: context.l10n.terminalOpenLink,
      ),
    if (linkUri != null) const TpActionMenuSpec.divider(),
    TpActionMenuSpec.item(
      value: 'paste',
      icon: Icons.content_paste,
      label: mloc.pasteButtonLabel,
    ),
    TpActionMenuSpec.item(
      value: 'copy',
      icon: Icons.content_copy,
      label: (!hasSelection && mouseReporting)
          ? menuContext.l10n.terminalCopySelectHint
          : mloc.copyButtonLabel,
      enabled: hasSelection,
    ),
    ...selectionAiMenuSpecs(
      l10n: menuContext.l10n,
      copyEnabled: hasAi,
      askAiEnabled: hasAi,
      onCopyAsAiContext: () {
        unawaited(Clipboard.setData(ClipboardData(text: aiContext)));
      },
      onAskAi: () {
        unawaited(onAskAi(aiContext));
      },
    ),
    TpActionMenuSpec.item(
      value: 'selectAll',
      icon: Icons.select_all,
      label: mloc.selectAllButtonLabel,
    ),
  ];

  final selected = await showTpActionMenuFromSpecs<String>(
    context: menuContext,
    globalPosition: globalPosition,
    popUpAnimationStyle: const AnimationStyle(duration: Duration.zero),
    specs: specs,
  );
  if (!menuContext.mounted) return;
  switch (selected) {
    case 'find':
      onFindRequested();
    case 'clear':
      onClearTerminal();
    case 'openLink':
      if (linkUri != null) {
        await onOpenLink(linkUri);
      }
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
      await terminalController.selectAll();
    default:
      break;
  }
}
