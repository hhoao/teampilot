import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/history_mailbox_queued_strip.dart';
import 'package:teampilot/services/terminal/pending_user_message.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

Widget _host(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('shows queued row and drops when unread clears', (tester) async {
    final submissions = StreamController<PendingUserMessage>.broadcast();
    final unread = <String>{'mail-1'};
    PendingUserMessage? consumed;
    addTearDown(submissions.close);

    await tester.pumpWidget(
      _host(
        HistoryMailboxQueuedStrip(
          submissions: submissions.stream,
          isUnread: unread.contains,
          onConsumed: (msg) => consumed = msg,
          pollInterval: const Duration(milliseconds: 20),
        ),
      ),
    );

    expect(find.byKey(kSessionHistoryMailboxQueuedStripKey), findsNothing);

    submissions.add(const PendingUserMessage(id: 'mail-1', content: '继续'));
    await tester.pump();
    expect(find.byKey(kSessionHistoryMailboxQueuedStripKey), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);

    unread.remove('mail-1');
    await tester.pump(const Duration(milliseconds: 25));
    expect(find.byKey(kSessionHistoryMailboxQueuedStripKey), findsNothing);
    expect(consumed?.id, 'mail-1');
    expect(consumed?.content, '继续');
  });

  testWidgets('dismiss removes row without waiting for unread', (tester) async {
    final submissions = StreamController<PendingUserMessage>.broadcast();
    PendingUserMessage? consumed;
    addTearDown(submissions.close);

    await tester.pumpWidget(
      _host(
        HistoryMailboxQueuedStrip(
          submissions: submissions.stream,
          isUnread: (_) => true,
          onConsumed: (msg) => consumed = msg,
        ),
      ),
    );

    submissions.add(const PendingUserMessage(id: 'mail-2', content: 'hello'));
    await tester.pump();
    expect(find.text('hello'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('hello'), findsNothing);
    expect(consumed, isNull);
  });
}
