import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/workspace_terminal/workspace_terminal_empty_pane.dart';

void main() {
  testWidgets('empty pane offers New terminal and invokes callback', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: WorkspaceTerminalEmptyPane(
            foreground: Colors.white,
            onNewTerminal: () => tapped = true,
          ),
        ),
      ),
    );

    final l10n = AppLocalizations.of(
      tester.element(find.byType(WorkspaceTerminalEmptyPane)),
    );
    expect(find.text(l10n.workspaceTerminalNewSession), findsOneWidget);

    await tester.tap(find.text(l10n.workspaceTerminalNewSession));
    expect(tapped, isTrue);
  });
}
