import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'AiMarkdownLinkActionsScope delivers onLinkTap to AiTextPartView',
    (tester) async {
      String? tappedHref;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AiMessageTheme.test()]),
          home: Scaffold(
            body: AiMarkdownLinkActionsScope(
              actions: AiMarkdownLinkActions(
                onLinkTap: (href) async {
                  tappedHref = href;
                },
              ),
              child: const AiTextPartView(text: '[link](https://example.com)'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('link'));
      await tester.pump();
      expect(tappedHref, 'https://example.com');
    },
  );

  testWidgets('AiTextPartView without scope stays inert on link tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AiMessageTheme.test()]),
        home: const Scaffold(
          body: AiTextPartView(text: '[link](https://example.com)'),
        ),
      ),
    );

    expect(find.text('link'), findsOneWidget);
    await tester.tap(find.text('link'));
    await tester.pump();
    expect(find.text('link'), findsOneWidget);
  });
}
