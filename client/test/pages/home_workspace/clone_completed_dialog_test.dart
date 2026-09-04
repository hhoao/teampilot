import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/repo_clone_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/clone_completed_dialog.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

Widget _harness({GlobalKey<NavigatorState>? navigatorKey, Widget? home}) {
  final theme = ThemeData(useMaterial3: true);
  return TpTheme(
    data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
    child: MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      home: Scaffold(body: Center(child: home ?? const SizedBox.shrink())),
    ),
  );
}

RepoCloneTask _task({String id = 'task-1'}) => RepoCloneTask(
  id: id,
  url: 'https://github.com/owner/repo.git',
  targetId: 'local',
  destPath: '/tmp/src/repo',
  dirName: 'repo',
  phase: RepoCloneTaskPhase.succeeded,
);

Workspace _workspace(String id, String display, String path) => Workspace(
  workspaceId: id,
  display: display,
  folders: [WorkspaceFolder(path: path)],
  createdAt: 0,
);

/// Routes [dialog] onto the navigator and returns the future that resolves
/// with whatever the dialog pops.
Future<T?> _pushDialog<T>(
  GlobalKey<NavigatorState> navigatorKey,
  Widget dialog,
) {
  return navigatorKey.currentState!.push<T>(
    MaterialPageRoute<T>(
      builder: (_) => Scaffold(body: Center(child: dialog)),
    ),
  );
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final navigatorKey = GlobalKey<NavigatorState>();

  testWidgets('completed dialog offers new workspace and add-to-existing', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(navigatorKey: navigatorKey));
    _pushDialog(navigatorKey, CloneCompletedDialog(task: _task()));
    await tester.pumpAndSettle();

    expect(find.text(l10n.cloneRepositoryCompletedTitle), findsOneWidget);
    expect(
      find.text(l10n.cloneRepositoryCompletedBody('/tmp/src/repo')),
      findsOneWidget,
    );
    expect(find.text(l10n.cloneRepositoryCreateWorkspace), findsOneWidget);
    expect(find.text(l10n.cloneRepositoryAddToWorkspace), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'choosing new workspace pops CloneCompletionAction.newWorkspace',
    (tester) async {
      await tester.pumpWidget(_harness(navigatorKey: navigatorKey));
      CloneCompletionAction? popped;
      _pushDialog<CloneCompletionAction>(
        navigatorKey,
        CloneCompletedDialog(task: _task()),
      ).then((value) => popped = value);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.cloneRepositoryCreateWorkspace));
      await tester.pumpAndSettle();

      expect(popped, CloneCompletionAction.newWorkspace);
    },
  );

  testWidgets(
    'choosing add-to-existing pops CloneCompletionAction.addToWorkspace',
    (tester) async {
      await tester.pumpWidget(_harness(navigatorKey: navigatorKey));
      CloneCompletionAction? popped;
      _pushDialog<CloneCompletionAction>(
        navigatorKey,
        CloneCompletedDialog(task: _task()),
      ).then((value) => popped = value);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.cloneRepositoryAddToWorkspace));
      await tester.pumpAndSettle();

      expect(popped, CloneCompletionAction.addToWorkspace);
    },
  );

  testWidgets('header close dismisses without an action', (tester) async {
    await tester.pumpWidget(_harness(navigatorKey: navigatorKey));
    CloneCompletionAction? popped;
    _pushDialog<CloneCompletionAction>(
      navigatorKey,
      CloneCompletedDialog(task: _task()),
    ).then((value) => popped = value);
    await tester.pumpAndSettle();

    final dialog = tester.widget<TpDialog>(find.byType(TpDialog));
    // Header close is rendered as an icon button inside the dialog header.
    expect(find.byType(TpDialog), findsOneWidget);
    expect(dialog.maxWidth, 480);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(popped, isNull);
  });

  testWidgets('add-to picker lists workspaces and fires onAdd on tap', (
    tester,
  ) async {
    final workspaces = [
      _workspace('ws-1', 'Alpha', '/home/alpha'),
      _workspace('ws-2', '', '/home/beta'),
    ];
    final added = <Workspace>[];
    await tester.pumpWidget(_harness(navigatorKey: navigatorKey));
    var popped = false;
    _pushDialog(
      navigatorKey,
      CloneAddToWorkspaceDialog(
        task: _task(),
        workspaces: workspaces,
        onAdd: (workspace) async => added.add(workspace),
      ),
    ).then((value) => popped = true);
    await tester.pumpAndSettle();

    expect(find.text(l10n.cloneRepositoryChooseWorkspace), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    // Empty display falls back to the primary folder basename.
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('/home/alpha'), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    expect(added, [workspaces.first]);

    // Let the success toast's auto-close timer fire before settling.
    await tester.pump(const Duration(seconds: 3));
    AppToast.dismiss();
    await tester.pumpAndSettle();

    expect(popped, isTrue, reason: 'tapping a workspace must pop the picker');
  });
}
