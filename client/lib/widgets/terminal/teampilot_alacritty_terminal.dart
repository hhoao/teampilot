import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/floating_workspace/floating_panel_visibility.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/shortcut_cubit.dart';
import '../../services/commands/key_chord.dart';
import '../../services/commands/shortcut_context.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/commands/terminal_passthrough_shortcuts.dart';
import '../../services/terminal/terminal_fonts.dart';
import 'terminal_with_history_scrollbar.dart';

/// Shared Alacritty [TerminalView] shell for chat workbench and workspace dock.
///
/// Hosts own chrome around this (find bar, DnD, parked send, semantics).
/// [padding] stays host-specific — chat keeps a wider inset than the dock shell.
class TeampilotAlacrittyTerminal extends StatelessWidget {
  const TeampilotAlacrittyTerminal({
    required this.engine,
    required this.controller,
    required this.theme,
    required this.padding,
    required this.linkProviders,
    required this.onPtyResize,
    required this.onLinkActivate,
    required this.onSecondaryTapDown,
    this.terminalViewKey,
    this.autofocus = true,
    this.backgroundOpacity = 0.98,
    this.onTapDown,
    super.key,
  });

  final TerminalEngine engine;
  final TerminalController controller;
  final TerminalTheme theme;
  final EdgeInsets padding;
  final List<TerminalLinkProvider> linkProviders;
  final void Function(int columns, int rows) onPtyResize;
  final void Function(String uri) onLinkActivate;
  final void Function(TapDownDetails details, CellOffset? cell)
  onSecondaryTapDown;
  final Key? terminalViewKey;
  final bool autofocus;
  final double backgroundOpacity;
  final void Function(TapDownDetails details, CellOffset? cell)? onTapDown;

  @override
  Widget build(BuildContext context) {
    final shortcutCubit = context.watch<ShortcutCubit>();
    var floatingPanelOpen = false;
    try {
      floatingPanelOpen =
          context.watch<FloatingWorkspaceCubit>().state.visibility ==
          FloatingPanelVisibility.open;
    } catch (_) {
      // Terminal hosts outside the floating cubit (isolated tests).
    }
    final overlayContext = ShortcutContext(
      floatingPanelOpen: floatingPanelOpen && !isTpActionMenuOpen,
    );
    final terminalShortcuts = <ShortcutActivator, Intent>{
      ...defaultTerminalShortcuts,
      ...terminalPassthroughShortcutOverlay(
        effectiveByCommand: shortcutCubit.effective,
        isMacOS: defaultIsMacOS(),
        context: overlayContext,
      ),
    };
    return ShortcutFocus(
      kind: ShortcutFocusKind.terminal,
      child: TerminalWithHistoryScrollbar(
        engine: engine,
        controller: controller,
        child: TerminalView(
          engine,
          key: terminalViewKey,
          controller: controller,
          theme: theme,
          backgroundOpacity: backgroundOpacity,
          padding: padding,
          textStyle: appTerminalTextStyle(context),
          autofocus: autofocus,
          shortcuts: terminalShortcuts,
          linkProviders: linkProviders,
          primaryTapActivatesLink: context
              .watch<SessionPreferencesCubit>()
              .state
              .preferences
              .terminalLinkClickOpensInApp,
          onPtyResize: onPtyResize,
          onTapDown: onTapDown,
          onLinkActivate: onLinkActivate,
          onSecondaryTapDown: onSecondaryTapDown,
        ),
      ),
    );
  }
}
