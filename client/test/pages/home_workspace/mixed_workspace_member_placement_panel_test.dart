import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';

import '../../support/test_home_target_controller.dart';

void main() {
  const mixedFolders = [
    WorkspaceFolder(path: '/local-proj'),
    WorkspaceFolder(path: '/remote-proj', targetId: 'ssh:p1'),
  ];

  const lead = TeamMemberConfig(id: 'team-lead', name: 'Lead');
  const dev = TeamMemberConfig(id: 'dev', name: 'Developer');

  group('canIncrementMemberPlacement', () {
    test('non-lead allows increment below per-host max', () {
      expect(
        canIncrementMemberPlacement(
          member: dev,
          folders: mixedFolders,
          selectedTargetId: WorkspaceFolder.localTargetId,
          countOnMachine: 5,
        ),
        isTrue,
      );
    });

    test('non-lead blocks increment at per-host max', () {
      expect(
        canIncrementMemberPlacement(
          member: dev,
          folders: mixedFolders,
          selectedTargetId: WorkspaceFolder.localTargetId,
          countOnMachine: memberPlacementMaxPerHost,
        ),
        isFalse,
      );
    });

    test('lead blocks increment on non-preferred host', () {
      expect(
        canIncrementMemberPlacement(
          member: lead,
          folders: mixedFolders,
          selectedTargetId: 'ssh:p1',
          countOnMachine: 0,
        ),
        isFalse,
      );
    });

    test('lead allows increment to 1 on preferred host', () {
      expect(
        canIncrementMemberPlacement(
          member: lead,
          folders: mixedFolders,
          selectedTargetId: WorkspaceFolder.localTargetId,
          countOnMachine: 0,
        ),
        isTrue,
      );
    });

    test('lead blocks increment when already placed on preferred host', () {
      expect(
        canIncrementMemberPlacement(
          member: lead,
          folders: mixedFolders,
          selectedTargetId: WorkspaceFolder.localTargetId,
          countOnMachine: 1,
        ),
        isFalse,
      );
    });
  });

  group('canDecrementMemberPlacement', () {
    test('non-lead allows decrement above zero on host', () {
      expect(
        canDecrementMemberPlacement(
          member: dev,
          folders: mixedFolders,
          selectedTargetId: WorkspaceFolder.localTargetId,
          countOnMachine: 3,
        ),
        isTrue,
      );
    });

    test('non-lead blocks decrement at zero on host', () {
      expect(
        canDecrementMemberPlacement(
          member: dev,
          folders: mixedFolders,
          selectedTargetId: WorkspaceFolder.localTargetId,
          countOnMachine: 0,
        ),
        isFalse,
      );
    });

    test('lead blocks decrement on preferred host', () {
      expect(
        canDecrementMemberPlacement(
          member: lead,
          folders: mixedFolders,
          selectedTargetId: WorkspaceFolder.localTargetId,
          countOnMachine: 1,
        ),
        isFalse,
      );
    });

    test('lead allows decrement on non-preferred host', () {
      expect(
        canDecrementMemberPlacement(
          member: lead,
          folders: mixedFolders,
          selectedTargetId: 'ssh:p1',
          countOnMachine: 1,
        ),
        isTrue,
      );
    });
  });

  testWidgets('panel increments non-lead without profile replica cap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var placement = defaultMemberPlacement(
      folders: mixedFolders,
      members: const [lead, dev],
    );
    final workspace = Workspace(
      workspaceId: 'ws-1',
      folders: mixedFolders,
      createdAt: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepositoryProvider<HomeTargetController>.value(
          value: testHomeTargetController(),
          child: StatefulBuilder(
            builder: (context, setState) {
              return MixedWorkspaceMemberPlacementPanel(
                workspace: workspace,
                members: const [lead, dev],
                placement: placement,
                onPlacementChanged: (next) => setState(() => placement = next),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final devRow = find.ancestor(
      of: find.text('Developer'),
      matching: find.byType(ListTile),
    );
    expect(devRow, findsOneWidget);

    final addButtons = find.descendant(
      of: devRow,
      matching: find.widgetWithIcon(IconButton, Icons.add),
    );
    expect(addButtons, findsOneWidget);

    await tester.tap(addButtons);
    await tester.pump();

    expect(placement[WorkspaceFolder.localTargetId]?['dev'], 1);
    expect(memberPlacementCountForType(placement, 'dev'), 1);
  });

  testWidgets('panel locks lead on preferred host', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var placement = defaultMemberPlacement(
      folders: mixedFolders,
      members: const [lead, dev],
    );
    final workspace = Workspace(
      workspaceId: 'ws-1',
      folders: mixedFolders,
      createdAt: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepositoryProvider<HomeTargetController>.value(
          value: testHomeTargetController(),
          child: StatefulBuilder(
            builder: (context, setState) {
              return MixedWorkspaceMemberPlacementPanel(
                workspace: workspace,
                members: const [lead, dev],
                placement: placement,
                onPlacementChanged: (next) => setState(() => placement = next),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final leadRow = find.ancestor(
      of: find.text('Lead'),
      matching: find.byType(ListTile),
    );
    final leadMinus = find.descendant(
      of: leadRow,
      matching: find.widgetWithIcon(IconButton, Icons.remove),
    );
    final leadPlus = find.descendant(
      of: leadRow,
      matching: find.widgetWithIcon(IconButton, Icons.add),
    );

    expect(tester.widget<IconButton>(leadMinus).onPressed, isNull);
    expect(tester.widget<IconButton>(leadPlus).onPressed, isNull);

    await tester.tap(find.text('ssh:p1'));
    await tester.pump();

    final remoteLeadRow = find.ancestor(
      of: find.text('Lead'),
      matching: find.byType(ListTile),
    );
    final remoteLeadPlus = find.descendant(
      of: remoteLeadRow,
      matching: find.widgetWithIcon(IconButton, Icons.add),
    );
    expect(tester.widget<IconButton>(remoteLeadPlus).onPressed, isNull);
  });
}
