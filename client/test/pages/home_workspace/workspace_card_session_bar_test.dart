import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/launch_profile_ref.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';
import 'package:teampilot/pages/home_workspace/workspace_card_session_bar.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

void main() {
  final identities = [
    PersonalProfile(
      id: LaunchProfileProvisioner.defaultPersonalId,
      display: 'Personal',
      createdAt: 0,
    ),
    TeamProfile(
      id: 'team-alpha',
      name: 'Alpha Team',
      cli: CliTool.claude,
      members: const [],
      createdAt: 0,
    ),
  ];

  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  testWidgets('session bar shows count and context icon for recent cards', (
    tester,
  ) async {
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
          tabIdentity: const LaunchProfileRef('team-alpha'),
          launchProfiles: identities,
          showContextIcon: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 sessions'), findsOneWidget);
    expect(find.byType(WorkspaceTabKindTopologyIcon), findsOneWidget);
    expect(find.text('Remote workspace'), findsNothing);
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
    expect(find.byType(WorkspaceTabKindTopologyIcon), findsNothing);
  });

  testWidgets('session bar resolves identity from workspace default', (
    tester,
  ) async {
    final workspace = Workspace(
      workspaceId: 'p1',
      folders: [WorkspaceFolder(path: '/home/user/app')],
      defaultProfileId: 'team-alpha',
      createdAt: 1,
    );

    await tester.pumpWidget(
      wrap(
        WorkspaceCardSessionBar(
          sessionCount: 2,
          sessionCountLabel: 'sessions',
          workspace: workspace,
          launchProfiles: identities,
          showContextIcon: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 sessions'), findsOneWidget);
    expect(find.byType(WorkspaceTabKindTopologyIcon), findsOneWidget);
  });

  testWidgets('topology-only mode uses topology glyph without identities', (
    tester,
  ) async {
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
          sessionCount: 1,
          sessionCountLabel: 'sessions',
          workspace: workspace,
          showContextIcon: true,
          topologyIconOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
    expect(find.byType(WorkspaceTabKindTopologyIcon), findsNothing);
  });
}
