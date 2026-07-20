import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_tab_scope.dart';
import 'package:teampilot/pages/home_workspace/open_workspace_tab_actions.dart';

void main() {
  testWidgets('openWorkspace navigates via tab scope without blocking', (
    tester,
  ) async {
    final opened = <({String id, bool activate})>[];
    final workspace = Workspace(
      workspaceId: 'ws-1',
      folders: [WorkspaceFolder(path: '/tmp/ws')],
      display: 'ws',
      createdAt: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabScope(
          openWorkspace: (workspaceId, {bool activate = true}) {
            opened.add((id: workspaceId, activate: activate));
          },
          child: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  // Must return promptly — no await on session hydrate.
                  openWorkspace(context, workspace);
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();

    expect(opened, [(id: 'ws-1', activate: true)]);
  });
}
