import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/repositories/keybinding_repository.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/command_tooltip.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/key_chord_formatter.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<String> pumpLabel(
    WidgetTester tester, {
    required String label,
    required String commandId,
    ShortcutCubit? shortcuts,
  }) async {
    late String result;
    await tester.pumpWidget(
      shortcuts == null
          ? MaterialApp(
              home: Builder(
                builder: (context) {
                  result = commandTooltip(context, label, commandId);
                  return const SizedBox.shrink();
                },
              ),
            )
          : BlocProvider<ShortcutCubit>.value(
              value: shortcuts,
              child: MaterialApp(
                home: Builder(
                  builder: (context) {
                    result = commandTooltip(context, label, commandId);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
    );
    return result;
  }

  testWidgets('appends formatted default chord', (tester) async {
    final shortcuts = ShortcutCubit(repository: KeybindingRepository());
    addTearDown(shortcuts.close);
    await tester.runAsync(() => shortcuts.load());

    final chord = formatKeyChord(
      KeyChord(key: 'b', mods: [KeyChordMod.mod]),
      isMacOS: defaultIsMacOS(),
    );
    final result = await pumpLabel(
      tester,
      label: 'Hide sidebar',
      commandId: CommandIds.toggleSidebar,
      shortcuts: shortcuts,
    );
    expect(result, 'Hide sidebar ($chord)');
  });

  testWidgets('returns label only when unbound', (tester) async {
    final shortcuts = ShortcutCubit(repository: KeybindingRepository());
    addTearDown(shortcuts.close);
    await tester.runAsync(() => shortcuts.load());
    await tester.runAsync(() => shortcuts.unbind(CommandIds.toggleSidebar));

    final result = await pumpLabel(
      tester,
      label: 'Hide sidebar',
      commandId: CommandIds.toggleSidebar,
      shortcuts: shortcuts,
    );
    expect(result, 'Hide sidebar');
  });

  testWidgets('returns label only without ShortcutCubit', (tester) async {
    final result = await pumpLabel(
      tester,
      label: 'Hide sidebar',
      commandId: CommandIds.toggleSidebar,
    );
    expect(result, 'Hide sidebar');
  });

  testWidgets('formats double-tap Shift for workspace search', (tester) async {
    final shortcuts = ShortcutCubit(repository: KeybindingRepository());
    addTearDown(shortcuts.close);
    await tester.runAsync(() => shortcuts.load());

    final chord = formatKeyChord(
      KeyChord.doubleTapShift(),
      isMacOS: defaultIsMacOS(),
    );
    final result = await pumpLabel(
      tester,
      label: 'Search',
      commandId: CommandIds.workspaceSearch,
      shortcuts: shortcuts,
    );
    expect(result, 'Search ($chord)');
  });
}
