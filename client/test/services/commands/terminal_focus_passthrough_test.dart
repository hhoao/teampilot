import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/shortcut_context.dart';
import 'package:teampilot/services/commands/shortcut_dispatcher.dart';
import 'package:teampilot/services/commands/shortcut_focus.dart';

/// End-to-end regression test for Task 11 (terminal focus tagging +
/// passthrough verification).
///
/// Drives a real [ShortcutDispatcher] installed on [HardwareKeyboard] (like
/// `ShortcutDispatcherHost` in `main.dart`) against widgets wrapped in
/// [ShortcutFocus], deriving `inTerminal` / `inCompose` from
/// [FocusManager.instance.primaryFocus] exactly the way `main.dart`'s
/// private `_liveShortcutContext` / `_primaryShortcutFocusKind` do — proving
/// that a `terminalPassthrough: true` command (`sessionNextTab`, Ctrl+Tab)
/// still fires while focus sits under a `ShortcutFocus.terminal` ancestor,
/// while `compose.submit` (bare Enter, `when: inCompose`) never does, since
/// `inTerminal` and `inCompose` are mutually exclusive by construction.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PhysicalKeyboardKey physicalFor(LogicalKeyboardKey logicalKey) {
    return switch (logicalKey) {
      LogicalKeyboardKey.enter => PhysicalKeyboardKey.enter,
      LogicalKeyboardKey.tab => PhysicalKeyboardKey.tab,
      LogicalKeyboardKey.controlLeft => PhysicalKeyboardKey.controlLeft,
      _ => throw UnsupportedError('Add mapping for $logicalKey'),
    };
  }

  KeyDownEvent keyDown(LogicalKeyboardKey logicalKey) => KeyDownEvent(
    physicalKey: physicalFor(logicalKey),
    logicalKey: logicalKey,
    timeStamp: Duration.zero,
  );

  KeyUpEvent keyUp(LogicalKeyboardKey logicalKey) => KeyUpEvent(
    physicalKey: physicalFor(logicalKey),
    logicalKey: logicalKey,
    timeStamp: Duration.zero,
  );

  /// Mirrors `main.dart`'s `_primaryShortcutFocusKind` + `_liveShortcutContext`
  /// (private, so re-implemented here against the same public
  /// `ShortcutFocus.maybeOf` seam those functions use).
  ShortcutContext liveContext() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final kind = focusContext == null
        ? null
        : ShortcutFocus.maybeOf(focusContext)?.kind;
    return ShortcutContext(
      inTerminal: kind == ShortcutFocusKind.terminal,
      inCompose: kind == ShortcutFocusKind.compose,
      inTextInput:
          kind == ShortcutFocusKind.compose || kind == ShortcutFocusKind.text,
      hasWorkspace: true,
    );
  }

  late FocusNode terminalFocusNode;
  late FocusNode composeFocusNode;

  Future<void> pumpFocusRegions(WidgetTester tester) async {
    terminalFocusNode = FocusNode(debugLabel: 'fake-terminal');
    composeFocusNode = FocusNode(debugLabel: 'fake-compose');
    addTearDown(() {
      terminalFocusNode.dispose();
      composeFocusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // Stand-in for `ChatWorkbenchRunningTerminal` /
              // `WorkspaceTerminalView`'s `ShortcutFocus(kind: terminal, ...)`
              // wrapper — the real widgets wrap a `flutter_alacritty`
              // `TerminalView`; this test only needs something focusable
              // under the same `ShortcutFocus` ancestor.
              ShortcutFocus(
                kind: ShortcutFocusKind.terminal,
                child: Focus(focusNode: terminalFocusNode, child: const SizedBox()),
              ),
              ShortcutFocus(
                kind: ShortcutFocusKind.compose,
                child: Focus(focusNode: composeFocusNode, child: const SizedBox()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ShortcutDispatcher installDispatcher(CommandBus bus) {
    final dispatcher = ShortcutDispatcher(
      bus: bus,
      effectiveChords: (commandId) => CommandCatalog.v1
          .firstWhere((def) => def.id == commandId)
          .defaultChords,
      context: liveContext,
      isMacOS: () => false,
    );
    dispatcher.attach();
    return dispatcher;
  }

  testWidgets(
    'terminalPassthrough command fires while focus is under '
    'ShortcutFocus.terminal, compose.submit does not',
    (tester) async {
      await pumpFocusRegions(tester);

      final bus = CommandBus();
      var sessionNextTabCalls = 0;
      var composeSubmitCalls = 0;
      bus.register(CommandIds.sessionNextTab, () => sessionNextTabCalls++);
      bus.register(CommandIds.composeSubmit, () => composeSubmitCalls++);
      final dispatcher = installDispatcher(bus);
      addTearDown(dispatcher.detach);

      terminalFocusNode.requestFocus();
      await tester.pump();

      // Ctrl+Tab -> sessionNextTab (terminalPassthrough: true) fires even
      // though primary focus resolves to ShortcutFocusKind.terminal.
      HardwareKeyboard.instance.handleKeyEvent(
        keyDown(LogicalKeyboardKey.controlLeft),
      );
      dispatcher.handle(keyDown(LogicalKeyboardKey.tab));
      HardwareKeyboard.instance.handleKeyEvent(
        keyUp(LogicalKeyboardKey.controlLeft),
      );

      expect(sessionNextTabCalls, 1);

      // Bare Enter (no modifiers held) -> compose.submit requires
      // `when: inCompose`; focus is in the terminal region, not compose,
      // so it must not fire.
      dispatcher.handle(keyDown(LogicalKeyboardKey.enter));

      expect(composeSubmitCalls, 0);

      // Move focus to the compose region: inCompose flips true, inTerminal
      // flips false — the same bare Enter now submits.
      composeFocusNode.requestFocus();
      await tester.pump();

      dispatcher.handle(keyDown(LogicalKeyboardKey.enter));

      expect(composeSubmitCalls, 1);
    },
  );
}
