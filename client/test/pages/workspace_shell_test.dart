import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';

Widget _wrapShell(Widget shell) {
  return MaterialApp(
    home: BlocProvider(
      create: (_) => LayoutCubit(),
      child: Scaffold(body: shell),
    ),
  );
}

void main() {
  testWidgets('workspace shell renders child without transition animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapShell(
        const WorkspaceShell(
          showHeader: false,
          breadcrumb: 'Team / Chat',
          title: 'Chat',
          subtitle: 'Terminal',
          actions: [],
          child: Text('Terminal body'),
        ),
      ),
    );

    expect(find.text('Terminal body'), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });

  testWidgets('hides tab row when tabs empty and new-chat button off', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapShell(
        const WorkspaceShell(
          showHeader: false,
          breadcrumb: 'Team / Chat',
          title: 'Chat',
          subtitle: 'Terminal',
          actions: [],
          showNewChatButton: false,
          child: Text('Compose'),
        ),
      ),
    );

    expect(find.byType(WorkspaceShellTabRow), findsNothing);
    expect(find.byType(WorkspaceShellNewChatButton), findsNothing);
  });

  testWidgets('shows tab row when tabs empty but new-chat button on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapShell(
        const WorkspaceShell(
          showHeader: false,
          breadcrumb: 'Team / Chat',
          title: 'Chat',
          subtitle: 'Terminal',
          actions: [],
          showNewChatButton: true,
          newChatTooltip: 'New',
          child: Text('Compose'),
        ),
      ),
    );

    expect(find.byType(WorkspaceShellTabRow), findsOneWidget);
    expect(find.byType(WorkspaceShellNewChatButton), findsOneWidget);
  });

  testWidgets('shows tab row and new-chat when tabs present', (tester) async {
    await tester.pumpWidget(
      _wrapShell(
        const WorkspaceShell(
          showHeader: false,
          breadcrumb: 'Team / Chat',
          title: 'Chat',
          subtitle: 'Terminal',
          actions: [],
          showNewChatButton: true,
          newChatTooltip: 'New',
          tabs: [TabInfo(id: 's1', title: 'Session')],
          child: Text('Session body'),
        ),
      ),
    );

    expect(find.byType(WorkspaceShellTabRow), findsOneWidget);
    expect(find.byType(WorkspaceShellNewChatButton), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);
  });
}
