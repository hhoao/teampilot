import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_compose_landing_pane.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_ide_center.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_skeleton.dart';

void main() {
  final workspace = Workspace(
    workspaceId: 'ws-1',
    folders: [WorkspaceFolder(path: '/tmp/ws')],
    display: 'ws',
    createdAt: 1,
  );

  test('compose landing picks WorkspaceComposeLandingPane', () {
    final center = buildWorkspaceIdeCenter(
      composeLanding: true,
      workspace: workspace,
      chatPage: const Text('chat-page'),
    );
    expect(center, isA<WorkspaceComposeLandingPane>());
  });

  test('session workbench keeps ChatPage child', () {
    const chat = Text('chat-page');
    final center = buildWorkspaceIdeCenter(
      composeLanding: false,
      workspace: workspace,
      chatPage: chat,
    );
    expect(identical(center, chat), isTrue);
  });

  test('sidebar list body is deferred with session skeleton', () {
    final source = File(
      'lib/pages/home_workspace/workspace/workspace_sidebar.dart',
    ).readAsStringSync();
    expect(source.contains('TpDeferredMountShell('), isTrue);
    expect(source.contains('placeholder: const _SessionListSkeleton()'), isTrue);
  });

  test('landing body defers one frame after sidebar list', () {
    final source = File(
      'lib/pages/home_workspace/workspace/workspace_compose_landing_pane.dart',
    ).readAsStringSync();
    // Sidebar uses delayFrames: 1; landing uses 2 so #791-style frames split.
    expect(
      RegExp(r'TpDeferredMountShell\(\s*delayFrames:\s*2,').hasMatch(source),
      isTrue,
    );
  });

  testWidgets('WorkspaceLandingSkeleton paints without TextField', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: TpTheme(
          data: TpThemeData.fromColorScheme(scheme, scale: 1),
          child: const Scaffold(body: WorkspaceLandingSkeleton()),
        ),
      ),
    );

    expect(find.byType(WorkspaceLandingSkeleton), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('landing defer uses TpDeferredMountShell + skeleton placeholder', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: TpTheme(
          data: TpThemeData.fromColorScheme(scheme, scale: 1),
          child: TpDeferredMountShell(
            delayFrames: 2,
            placeholder: const WorkspaceLandingSkeleton(),
            child: const Text('landing-body'),
          ),
        ),
      ),
    );

    expect(find.byType(TpDeferredMountShell), findsOneWidget);
    // FLUTTER_TEST mounts child immediately.
    expect(find.text('landing-body'), findsOneWidget);
  });
}
