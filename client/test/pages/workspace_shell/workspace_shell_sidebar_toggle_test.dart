import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/repositories/keybinding_repository.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/key_chord_formatter.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(() {
    setUpTestAppStorage();
  });
  tearDown(() {
    tearDownTestAppStorage();
  });

  testWidgets(
    'sidebar toggle uses effectiveOpen with narrowLeftSuppressed',
    (tester) async {
      final layout = LayoutCubit();
      final shortcuts = ShortcutCubit(repository: KeybindingRepository());
      addTearDown(layout.close);
      addTearDown(shortcuts.close);
      await layout.setSidebarVisible(true);
      layout.setNarrowLeftSuppressed(true);
      await tester.runAsync(() => shortcuts.load());

      final theme = ThemeData(useMaterial3: true);

      await tester.pumpWidget(
        TpTheme(
          data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<LayoutCubit>.value(value: layout),
              BlocProvider<ShortcutCubit>.value(value: shortcuts),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: theme,
              home: const Scaffold(
                body: WorkspaceShellSidebarVisibilityToggle(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final expectedChord = formatKeyChord(
        KeyChord(key: 'b', mods: [KeyChordMod.mod]),
        isMacOS: defaultIsMacOS(),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(AppKeys.sidebarVisibilityButton)),
      );
      expect(
        tester
            .widget<TpIconButton>(find.byKey(AppKeys.sidebarVisibilityButton))
            .tooltip,
        '${l10n.sidebarPanelVisible} ($expectedChord)',
      );

      final button = tester.widget<TpIconButton>(
        find.byKey(AppKeys.sidebarVisibilityButton),
      );
      expect(button.selected, isFalse);

      await tester.tap(find.byKey(AppKeys.sidebarVisibilityButton));
      await tester.pumpAndSettle();

      expect(layout.state.narrowLeftSuppressed, isFalse);
      expect(layout.state.preferences.sidebarVisible, isTrue);

      final buttonAfterClear = tester.widget<TpIconButton>(
        find.byKey(AppKeys.sidebarVisibilityButton),
      );
      expect(buttonAfterClear.selected, isTrue);

      await tester.tap(find.byKey(AppKeys.sidebarVisibilityButton));
      await tester.pumpAndSettle();

      expect(layout.state.preferences.sidebarVisible, isFalse);
      expect(layout.state.narrowLeftSuppressed, isFalse);
      expect(
        tester.widget<TpIconButton>(find.byKey(AppKeys.sidebarVisibilityButton)).selected,
        isFalse,
      );
    },
  );
}
