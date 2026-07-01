import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/widgets/right_tools/tabbed_panel.dart';
import 'package:teampilot/widgets/right_tools/tool_view.dart';

void main() {
  testWidgets('shows persisted selection on first frame without a second tap',
      (tester) async {
    final toolsCubit = WorkspaceToolsCubit()..setSelectedIndex('ws-1', 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: toolsCubit,
            child: TabbedPanel(
              scopeId: 'ws-1',
              views: const [
                ToolView(
                  icon: Icons.groups_outlined,
                  label: 'Members',
                  child: Text('members-body'),
                ),
                ToolView(
                  icon: Icons.mail_outline,
                  label: 'Mailbox',
                  child: Text('mailbox-body'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('mailbox-body'), findsOneWidget);
    addTearDown(toolsCubit.close);
  });

  testWidgets('switches the visible view when an icon is tapped',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TabbedPanel(views: const [
          ToolView(
              icon: Icons.groups_outlined,
              label: 'Members',
              child: Text('members-body')),
          ToolView(
              icon: Icons.mail_outline,
              label: 'Mailbox',
              child: Text('mailbox-body'),
              badgeCount: 3),
        ]),
      ),
    ));

    expect(find.text('members-body'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mail_outline));
    await tester.pump();
    expect(find.text('mailbox-body'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // badge
  });
}
