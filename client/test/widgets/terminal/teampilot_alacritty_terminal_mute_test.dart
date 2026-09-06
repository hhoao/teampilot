import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/render/mirror_grid.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/perf/terminal_render_mute.dart';
import 'package:teampilot/widgets/terminal/teampilot_alacritty_terminal.dart';
import '../../support/rust_lib_test_init.dart';

void _applyBlankGrid(TerminalEngine engine, {int cursorCol = 0}) {
  const rows = 4;
  const columns = 8;
  engine.gridForView.apply(
    GridUpdate(
      full: true,
      rows: rows,
      columns: columns,
      lines: [
        for (var i = 0; i < rows; i++)
          LineCells(
            line: i,
            codepoints: Uint32List.fromList(List.filled(columns, 0x20)),
            fg: Uint32List.fromList(List.filled(columns, 0xD8D8D8)),
            bg: Uint32List.fromList(List.filled(columns, 0x181818)),
            flags: Uint16List.fromList(List.filled(columns, 0)),
          ),
      ],
      cursorRow: 0,
      cursorCol: cursorCol,
      cursorVisible: true,
    ),
  );
}

/// Pumps [TeampilotAlacrittyTerminal] with the render-mute flag toggled.
/// Returns the engine so tests can drive grid updates through it.
Future<TerminalEngine> _pumpTerminal(
  WidgetTester tester, {
  required bool muted,
}) async {
  TerminalRenderMute.debugOverride = muted;
  addTearDown(() => TerminalRenderMute.debugOverride = null);

  final engine = TerminalEngine(config: TerminalConfig.defaults());
  addTearDown(engine.dispose);
  final controller = TerminalController()..attach(engine);
  addTearDown(controller.dispose);

  Widget terminal = TeampilotAlacrittyTerminal(
    engine: engine,
    controller: controller,
    theme: TerminalConfig.defaults().theme,
    padding: EdgeInsets.zero,
    linkProviders: const [],
    onPtyResize: (_, _) {},
    onLinkActivate: (_) {},
    onSecondaryTapDown: (_, _) {},
  );
  if (!muted) {
    // Unmuted build reads shortcut/session-preferences/floating-workspace
    // cubits; the muted placeholder must not require any of them.
    // Mock the platform channel: an unmocked SharedPreferences.getInstance()
    // awaits a real MethodChannel reply that never arrives under
    // flutter_tester, which hangs the fake-async test for good.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final sessionPreferences = SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
    );
    addTearDown(sessionPreferences.close);
    final shortcuts = ShortcutCubit();
    addTearDown(shortcuts.close);
    final floatingWorkspace = FloatingWorkspaceCubit();
    addTearDown(floatingWorkspace.close);
    terminal = MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sessionPreferences),
        BlocProvider.value(value: shortcuts),
        BlocProvider.value(value: floatingWorkspace),
      ],
      child: terminal,
    );
  }

  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: terminal)),
  );
  return engine;
}

void main() {
  setUpAll(initRustLibForTests);

  test('TerminalRenderMute disabled by default', () {
    TerminalRenderMute.debugOverride = null;
    expect(TerminalRenderMute.enabled, isFalse);
  });

  testWidgets('muted: TerminalView not mounted, grid ticks schedule no frame', (
    tester,
  ) async {
    final engine = await _pumpTerminal(tester, muted: true);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    expect(find.byType(TerminalView), findsNothing);
    expect(
      find.text('terminal render muted (PERF_MUTE_TERMINALS)'),
      findsOneWidget,
    );

    // Grid updates from PTY output must not schedule repaints: with no
    // TerminalView mounted, the mirror grid has zero listeners.
    _applyBlankGrid(engine, cursorCol: 3);
    await tester.pump();
    _applyBlankGrid(engine, cursorCol: 5);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('unmuted: TerminalView mounts and grid ticks schedule frames', (
    tester,
  ) async {
    final engine = await _pumpTerminal(tester, muted: false);
    // Fixed pumps, not pumpAndSettle: the live terminal schedules continuous
    // frames (cursor blink, post-frame atlas raster), so the tree never
    // settles — itself evidence of why the muted placeholder is needed.
    await tester.pump();
    await tester.pump();

    expect(find.byType(TerminalView), findsOneWidget);
    expect(
      find.text('terminal render muted (PERF_MUTE_TERMINALS)'),
      findsNothing,
    );

    _applyBlankGrid(engine, cursorCol: 3);
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: 'unmuted grid ticks must reach the painter repaint listeners',
    );
  });
}
