import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/workspace_terminal/workspace_terminal_empty_pane.dart';

void main() {
  testWidgets('empty pane offers New terminal and invokes callback', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appLocalizationsSupportedLocales,
        home: Scaffold(
          body: WorkspaceTerminalEmptyPane(
            foreground: Colors.white,
            onNewTerminal: () => tapped = true,
          ),
        ),
      ),
    );

    final l10n = tester.element(find.byType(WorkspaceTerminalEmptyPane)).l10n;
    expect(find.text(l10n.workspace.terminalNewSession), findsOneWidget);

    // The empty launcher is the only affordance in an otherwise blank terminal
    // body, so it uses readable body text + a matching icon size.
    final styles = TpTextStyles.of(
      tester.element(find.byType(WorkspaceTerminalEmptyPane)),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.terminal_outlined));
    expect(icon.size, 22);
    final label = tester.widget<Text>(
      find.text(l10n.workspace.terminalNewSession),
    );
    expect(label.style?.fontSize, styles.mdMedium.fontSize);
    expect(label.style?.fontWeight, FontWeight.w500);

    await tester.tap(find.text(l10n.workspace.terminalNewSession));
    expect(tapped, isTrue);
  });
}
