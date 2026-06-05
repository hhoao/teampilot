import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/right_tools/tabbed_panel.dart';
import 'package:teampilot/widgets/right_tools/tool_view.dart';

void main() {
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
