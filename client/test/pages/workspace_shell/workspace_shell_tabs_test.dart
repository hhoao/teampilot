import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/repositories/keybinding_repository.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/key_chord_formatter.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  testWidgets(
    'right-tools toggle uses its explicit workspace while chat scope is stale',
    (tester) async {
      setUpTestAppStorage();
      addTearDown(tearDownTestAppStorage);

      final chat = testChatCubit(executableResolver: () => 'claude');
      final layout = LayoutCubit();
      final workbench = WorkbenchCubit()..enterLanding('landing-workspace');
      final shortcuts = ShortcutCubit(repository: KeybindingRepository());
      addTearDown(chat.close);
      addTearDown(layout.close);
      addTearDown(workbench.close);
      addTearDown(shortcuts.close);

      chat.setActiveWorkspace('previous-workspace');
      await tester.runAsync(() => shortcuts.load());

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ChatCubit>.value(value: chat),
            BlocProvider<LayoutCubit>.value(value: layout),
            BlocProvider<WorkbenchCubit>.value(value: workbench),
            BlocProvider<ShortcutCubit>.value(value: shortcuts),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: WorkspaceShellRightToolsVisibilityToggle(
                workspaceId: 'landing-workspace',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final expectedChord = formatKeyChord(
        KeyChord(
          key: 'b',
          mods: [KeyChordMod.mod, KeyChordMod.alt],
        ),
        isMacOS: defaultIsMacOS(),
      );
      final button = tester.widget<TpIconButton>(
        find.byKey(AppKeys.rightToolsVisibilityButton),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(AppKeys.rightToolsVisibilityButton)),
      )!;
      expect(
        button.tooltip,
        '${l10n.rightToolsPanelVisible} ($expectedChord)',
      );

      await tester.tap(find.byKey(AppKeys.rightToolsVisibilityButton));
      await tester.pump();

      expect(layout.state.landingRightToolsOverride, isTrue);
      expect(layout.state.preferences.rightToolsVisible, isFalse);
    },
  );
}
