import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/workspace/worktree_create_dialog.dart';
import 'package:teampilot/services/git/worktree_branch_options.dart';
import 'package:teampilot/services/git/worktree_create_result.dart';

const _localBranches = ['main', 'feat/x'];

Future<List<WorktreeBranchOption>> _loader(String repoPath) async =>
    mergeWorktreeBranchOptions(local: _localBranches, remote: const []);

Widget _host({
  required Widget home,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

void main() {
  testWidgets('create derives from HEAD when no branch is selected', (
    tester,
  ) async {
    WorktreeCreateResult? result;
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWorktreeCreateDialog(
                  context,
                  repoName: 'repo',
                  repoPath: '/repo',
                  layout: ({required repoName, required branch}) =>
                      '/root/worktrees/$repoName/$branch',
                  branchLoader: _loader,
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

    expect(find.text('New worktree'), findsOneWidget);

    // Default name suggestion filled in.
    expect(
      find.widgetWithText(TextField, 'main-wt'),
      findsOneWidget,
    );

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.existingBranch, isFalse);
    expect(result!.baseRef, isNull);
    expect(result!.branch, 'main-wt');
    expect(result!.worktreePath, '/root/worktrees/repo/main-wt');
  });

  testWidgets('random button fills the name with wt-<hex>', (tester) async {
    WorktreeCreateResult? result;
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWorktreeCreateDialog(
                  context,
                  repoName: 'repo',
                  repoPath: '/repo',
                  layout: ({required repoName, required branch}) =>
                      '/root/worktrees/$repoName/$branch',
                  branchLoader: _loader,
                  existingWorktreePaths: const [
                    '/root/worktrees/repo/main-wt',
                  ],
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

    await tester.tap(find.byTooltip('Random name'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(RegExp(r'^wt-[0-9a-f]{6}$').hasMatch(field.controller!.text), isTrue);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(result!.existingBranch, isFalse);
    expect(result!.baseRef, isNull);
  });

  testWidgets('picking a branch auto-fills the name and checks it out', (
    tester,
  ) async {
    WorktreeCreateResult? result;
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWorktreeCreateDialog(
                  context,
                  repoName: 'repo',
                  repoPath: '/repo',
                  layout: ({required repoName, required branch}) =>
                      '/root/worktrees/$repoName/$branch',
                  branchLoader: _loader,
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

    // Open the selector dropdown and pick feat/x.
    await tester.tap(find.byType(TpSelectWithCustomInput));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feat/x').last);
    await tester.pumpAndSettle();

    // The picked branch auto-fills the name field.
    expect(find.widgetWithText(TextField, 'feat/x'), findsOneWidget);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.existingBranch, isTrue);
    expect(result!.branch, 'feat/x');
    expect(result!.baseRef, isNull);
    expect(result!.worktreePath, '/root/worktrees/repo/feat/x');
  });

  testWidgets('custom selector value never clobbers an edited name', (
    tester,
  ) async {
    WorktreeCreateResult? result;
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWorktreeCreateDialog(
                  context,
                  repoName: 'repo',
                  repoPath: '/repo',
                  layout: ({required repoName, required branch}) =>
                      '/root/worktrees/$repoName/$branch',
                  branchLoader: _loader,
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

    // User edits the name first.
    await tester.enterText(find.byType(TextField), 'hotfix');
    await tester.pump();

    // Type feat/x into the selector's custom-input mode and confirm.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'feat/x');
    await tester.pump();
    await tester.tap(find.byTooltip('Confirm'));
    await tester.pumpAndSettle();

    // The edited name is preserved, not overwritten by the custom value.
    expect(find.widgetWithText(TextField, 'hotfix'), findsOneWidget);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.existingBranch, isFalse);
    expect(result!.branch, 'hotfix');
    expect(result!.baseRef, 'feat/x');
  });

  testWidgets('no start-conversation checkbox exists anymore', (tester) async {
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showWorktreeCreateDialog(
                context,
                repoName: 'repo',
                repoPath: '/repo',
                layout: ({required repoName, required branch}) =>
                    '/root/worktrees/$repoName/$branch',
                branchLoader: _loader,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('Start a conversation here after creating'),
      findsNothing,
    );
  });

  testWidgets('create with cleared name shows required error and stays open', (
    tester,
  ) async {
    WorktreeCreateResult? result;
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWorktreeCreateDialog(
                  context,
                  repoName: 'repo',
                  repoPath: '/repo',
                  layout: ({required repoName, required branch}) =>
                      '/root/worktrees/$repoName/$branch',
                  branchLoader: _loader,
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

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(l10n.formFieldRequired), findsOneWidget);
  });

  testWidgets('onSubmit keeps dialog open with progress until complete', (
    tester,
  ) async {
    WorktreeCreateResult? result;
    final completer = Completer<void>();

    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWorktreeCreateDialog(
                  context,
                  repoName: 'repo',
                  repoPath: '/repo',
                  layout: ({required repoName, required branch}) =>
                      '/root/worktrees/$repoName/$branch',
                  branchLoader: _loader,
                  onSubmit: (_) => completer.future,
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

    await tester.tap(find.text('Create'));
    await tester.pump();

    expect(find.text('Creating…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(result, isNull);

    completer.complete();
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.branch, 'main-wt');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('onSubmit failure shows error and re-enables the form', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await showWorktreeCreateDialog(
                  context,
                  repoName: 'repo',
                  repoPath: '/repo',
                  layout: ({required repoName, required branch}) =>
                      '/root/worktrees/$repoName/$branch',
                  branchLoader: _loader,
                  onSubmit: (_) => Future<void>.error('disk full'),
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

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.textContaining('disk full'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
