import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/widgets/file_tree/file_tree_import_dialogs.dart';

Widget _host({required Widget home}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
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

  testWidgets('progress dialog listens to stream and closes on completion', (
    tester,
  ) async {
    final progressController = StreamController<ImportProgress>.broadcast();
    final cancelRequested = ValueNotifier<bool>(false);
    ImportSummary? summary;

    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                summary = await showFileTreeImportProgressDialog(
                  context: context,
                  progress: progressController.stream,
                  cancelRequested: cancelRequested,
                  task: Future<ImportSummary>(() async {
                    progressController.add(
                      const ImportProgress(
                        completedItems: 1,
                        totalItems: 2,
                        currentName: 'one.txt',
                      ),
                    );
                    await Future<void>.delayed(Duration.zero);
                    progressController.add(
                      const ImportProgress(
                        completedItems: 2,
                        totalItems: 2,
                        currentName: 'two.txt',
                      ),
                    );
                    return const ImportSummary(succeeded: 2);
                  }),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();

    expect(find.text('Importing…'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(summary?.succeeded, 2);
    expect(find.text('Importing…'), findsNothing);

    await progressController.close();
    cancelRequested.dispose();
  });

  testWidgets('progress dialog Cancel sets cancel flag', (tester) async {
    final progressController = StreamController<ImportProgress>.broadcast();
    final cancelRequested = ValueNotifier<bool>(false);
    addTearDown(cancelRequested.dispose);

    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                unawaited(
                  showFileTreeImportProgressDialog(
                    context: context,
                    progress: progressController.stream,
                    cancelRequested: cancelRequested,
                    task: Completer<ImportSummary>().future,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(cancelRequested.value, isFalse);

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(cancelRequested.value, isTrue);

    await progressController.close();
  });
}
