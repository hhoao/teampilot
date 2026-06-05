import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/terminal/pending_user_message.dart';
import 'package:teampilot/widgets/terminal/parked_send_overlay.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Stack(children: [child])),
    );

void main() {
  testWidgets('shows a banner until the message is consumed', (tester) async {
    final controller = StreamController<PendingUserMessage>.broadcast();
    final unread = <String>{'m1'};
    addTearDown(controller.close);

    await tester.pumpWidget(_host(ParkedSendOverlay(
      submissions: controller.stream,
      isUnread: unread.contains,
      pollInterval: const Duration(milliseconds: 50),
    )));

    controller.add(const PendingUserMessage(id: 'm1', content: 'hello'));
    await tester.pump();
    expect(find.textContaining('hello'), findsOneWidget);

    // Consume it -> next poll removes the banner.
    unread.remove('m1');
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.textContaining('hello'), findsNothing);
  });

  testWidgets('manual dismiss removes the banner', (tester) async {
    final controller = StreamController<PendingUserMessage>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(_host(ParkedSendOverlay(
      submissions: controller.stream,
      isUnread: (_) => true,
      pollInterval: const Duration(milliseconds: 50),
    )));

    controller.add(const PendingUserMessage(id: 'm1', content: 'bye'));
    await tester.pump();
    expect(find.textContaining('bye'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.textContaining('bye'), findsNothing);
  });
}
