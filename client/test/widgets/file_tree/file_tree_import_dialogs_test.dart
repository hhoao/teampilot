import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/theme/team_pilot_toast_config.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import 'package:teampilot/widgets/file_tree/file_tree_import_dialogs.dart';

Widget _host({required Widget home}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

Widget _toastHost({required Widget home}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return TpToastWrapper(
    config: buildTeamPilotToastConfig(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorScheme: scheme),
      home: TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1),
        child: home,
      ),
    ),
  );
}

void main() {
  testWidgets('conflict dialog Skip returns skip choice', (tester) async {
    FileTreeImportConflictDialogResult? result;
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showFileTreeImportConflictDialog(
                  context,
                  destPath: '/workspace/foo.txt',
                  typeMismatch: false,
                  remainingConflicts: 2,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Skip'), findsOneWidget);
    expect(find.textContaining('foo.txt'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(result?.choice, ConflictChoice.skip);
    expect(result?.applyToRemaining, isFalse);
  });

  testWidgets('conflict dialog disables Overwrite when typeMismatch', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showFileTreeImportConflictDialog(
                  context,
                  destPath: '/workspace/dir',
                  typeMismatch: true,
                  remainingConflicts: 0,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final overwrite = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Overwrite'),
    );
    expect(overwrite.onPressed, isNull);
  });

  testWidgets('ConflictSession applies choice to remaining conflicts', (
    tester,
  ) async {
    final session = FileTreeImportConflictSession();
    ConflictChoice? first;
    ConflictChoice? second;

    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final resolver = session.resolver(context);
                first = await resolver(
                  destPath: '/workspace/a.txt',
                  sourceIsDirectory: false,
                  destIsDirectory: false,
                  typeMismatch: false,
                  remainingConflicts: 1,
                );
                second = await resolver(
                  destPath: '/workspace/b.txt',
                  sourceIsDirectory: false,
                  destIsDirectory: false,
                  typeMismatch: false,
                  remainingConflicts: 0,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(first, ConflictChoice.skip);
    expect(second, ConflictChoice.skip);
  });

  testWidgets('cancelled summary toast includes cancelled suffix', (
    tester,
  ) async {
    addTearDown(TpToast.dismiss);

    await tester.pumpWidget(
      _toastHost(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showFileTreeImportSummaryIfNeeded(
                  context,
                  const ImportSummary(
                    succeeded: 2,
                    skipped: 1,
                    cancelled: true,
                  ),
                );
              },
              child: const Text('toast'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('toast'));
    await tester.pumpAndSettle();

    expect(find.textContaining('cancelled'), findsOneWidget);

    TpToast.dismiss();
    await tester.pumpAndSettle();
  });
}
