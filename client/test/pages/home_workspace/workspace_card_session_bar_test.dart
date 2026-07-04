import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace_card_session_bar.dart';
import 'package:teampilot/widgets/workspace_topology_icon.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  testWidgets('session bar shows count and topology icon', (tester) async {
    final workspace = Workspace(
      workspaceId: 'p1',
      folders: [
        WorkspaceFolder(path: '/var/www', targetId: 'ssh:host'),
      ],
      display: 'Remote App',
      createdAt: 1,
    );

    await tester.pumpWidget(
      wrap(
        WorkspaceCardSessionBar(
          sessionCount: 3,
          sessionCountLabel: 'sessions',
          workspace: workspace,
          showContextIcon: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 sessions'), findsOneWidget);
    expect(find.byType(WorkspaceTopologyIcon), findsOneWidget);
  });

  testWidgets('session bar hides context icon when disabled', (tester) async {
    final workspace = Workspace(
      workspaceId: 'p1',
      folders: [WorkspaceFolder(path: '/home/user/app')],
      createdAt: 1,
    );

    await tester.pumpWidget(
      wrap(
        WorkspaceCardSessionBar(
          sessionCount: 0,
          sessionCountLabel: 'sessions',
          workspace: workspace,
          showContextIcon: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0 sessions'), findsOneWidget);
    expect(find.byType(WorkspaceTopologyIcon), findsNothing);
  });
}
