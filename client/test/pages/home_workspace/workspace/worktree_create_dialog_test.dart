import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
