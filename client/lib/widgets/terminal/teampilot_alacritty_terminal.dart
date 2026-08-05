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
import 'teampilot_terminal_accessory_host.dart';
import 'terminal_with_history_scrollbar.dart';

/// Shared Alacritty [TerminalView] shell for chat workbench and workspace dock.
///
/// Hosts own chrome around this (find bar, DnD, parked send, semantics).
/// [padding] stays host-specific — chat keeps a wider inset than the dock shell.
class TeampilotAlacrittyTerminal extends StatefulWidget {
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
  State<TeampilotAlacrittyTerminal> createState() =>
      _TeampilotAlacrittyTerminalState();
}

class _TeampilotAlacrittyTerminalState extends State<TeampilotAlacrittyTerminal> {
  ModifierLatch? _modifierLatch;
  GlobalKey<TerminalViewState>? _fallbackViewKey;

  ModifierLatch get _latch => _modifierLatch ??= ModifierLatch();

  GlobalKey<TerminalViewState> get _viewKey {
    final key = widget.terminalViewKey;
    if (key is GlobalKey<TerminalViewState>) {
      return key;
    }
    return _fallbackViewKey ??= GlobalKey<TerminalViewState>();
  }

  @override
  void initState() {
    super.initState();
  }

  Map<ShortcutActivator, Intent> _terminalShortcuts(BuildContext context) {
    final shortcutCubit = context.watch<ShortcutCubit>();
    var floatingPanelOpen = false;
    try {
      // select: ensureTab / tab changes must NOT rebuild every session terminal.
      floatingPanelOpen = context.select<FloatingWorkspaceCubit, bool>(
        (c) => c.state.visibility == FloatingPanelVisibility.open,
      );
    } catch (_) {
      // Terminal hosts outside the floating cubit (isolated tests).
    }
    final overlayContext = ShortcutContext(
      floatingPanelOpen: floatingPanelOpen && !isTpActionMenuOpen,
    );
    return <ShortcutActivator, Intent>{
      ...defaultTerminalShortcuts,
      ...terminalPassthroughShortcutOverlay(
        effectiveByCommand: shortcutCubit.effective,
        isMacOS: defaultIsMacOS(),
        context: overlayContext,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final touchShell = isTouchShell();

    final view = TerminalView(
      widget.engine,
      key: touchShell ? _viewKey : widget.terminalViewKey,
      controller: widget.controller,
      theme: widget.theme,
      backgroundOpacity: widget.backgroundOpacity,
      padding: widget.padding,
      textStyle: appTerminalTextStyle(context),
      autofocus: widget.autofocus,
      preferGpuSurface: false,
      shortcuts: _terminalShortcuts(context),
      linkProviders: widget.linkProviders,
      modifierLatch: touchShell ? _latch : null,
      primaryTapActivatesLink: context
          .watch<SessionPreferencesCubit>()
          .state
          .preferences
          .terminalLinkClickOpensInApp,
      onPtyResize: widget.onPtyResize,
      onTapDown: widget.onTapDown,
      onLinkActivate: widget.onLinkActivate,
      onSecondaryTapDown: widget.onSecondaryTapDown,
    );

    final content = ShortcutFocus(
      kind: ShortcutFocusKind.terminal,
      child: TerminalWithHistoryScrollbar(
        engine: widget.engine,
        controller: widget.controller,
        child: view,
      ),
    );

    if (!touchShell) {
      return content;
    }

    return TeampilotTerminalAccessoryHost(
      viewKey: _viewKey,
      latch: _latch,
      child: content,
    );
  }
}
