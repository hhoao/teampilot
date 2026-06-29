import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace_card_meta_row.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  testWidgets('shows primary directory path and local topology label', (
    tester,
  ) async {
    final workspace = Workspace(
      workspaceId: 'p1',
      folders: [WorkspaceFolder(path: '/home/user/my-app')],
      display: 'My App',
      createdAt: 1,
    );

    await tester.pumpWidget(
      wrap(WorkspaceCardMetaRow(workspace: workspace)),
    );
    await tester.pumpAndSettle();

    expect(find.text('/home/user/my-app'), findsOneWidget);
    expect(find.text('Local workspace'), findsOneWidget);
  });

  testWidgets('shows remote topology for ssh target folders', (tester) async {
    final workspace = Workspace(
      workspaceId: 'p2',
      folders: [
        WorkspaceFolder(path: '/var/www', targetId: 'ssh:profile-1'),
      ],
      createdAt: 1,
    );

    await tester.pumpWidget(
      wrap(WorkspaceCardMetaRow(workspace: workspace)),
    );
    await tester.pumpAndSettle();

    expect(find.text('/var/www'), findsOneWidget);
    expect(find.text('Remote workspace'), findsOneWidget);
  });

  testWidgets('shows not-selected label when primary path is empty', (
    tester,
  ) async {
    final workspace = Workspace(workspaceId: 'p3', createdAt: 1);

    await tester.pumpWidget(
      wrap(WorkspaceCardMetaRow(workspace: workspace)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No primary directory selected'), findsOneWidget);
    expect(find.text('Local workspace'), findsOneWidget);
  });
}
