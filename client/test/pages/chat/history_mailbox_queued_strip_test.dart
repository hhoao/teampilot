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

  testWidgets('prunes immediately when already consumed on add', (tester) async {
    final submissions = StreamController<PendingUserMessage>.broadcast();
    PendingUserMessage? consumed;
    addTearDown(submissions.close);

    await tester.pumpWidget(
      _host(
        HistoryMailboxQueuedStrip(
          submissions: submissions.stream,
          isUnread: (_) => false,
          onConsumed: (msg) => consumed = msg,
        ),
      ),
    );

    submissions.add(const PendingUserMessage(id: 'mail-fast', content: 'hi'));
    await tester.pump();
    expect(find.byKey(kSessionHistoryMailboxQueuedStripKey), findsNothing);
    expect(consumed?.id, 'mail-fast');
  });

  testWidgets('clearToken drops rows without onConsumed', (tester) async {
    final submissions = StreamController<PendingUserMessage>.broadcast();
    PendingUserMessage? consumed;
    var clearToken = 0;
    addTearDown(submissions.close);

    Widget strip() => HistoryMailboxQueuedStrip(
      submissions: submissions.stream,
      isUnread: (_) => true,
      clearToken: clearToken,
      onConsumed: (msg) => consumed = msg,
    );

    await tester.pumpWidget(_host(strip()));
    submissions.add(const PendingUserMessage(id: 'mail-seat', content: 'x'));
    await tester.pump();
    expect(find.text('x'), findsOneWidget);

    clearToken = 1;
    await tester.pumpWidget(_host(strip()));
    await tester.pump();
    expect(find.text('x'), findsNothing);
    expect(consumed, isNull);
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

  testWidgets('dismiss then consume calls onConsumed', (tester) async {
    final submissions = StreamController<PendingUserMessage>.broadcast();
    final unread = <String>{'mail-3'};
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

    submissions.add(const PendingUserMessage(id: 'mail-3', content: 'later'));
    await tester.pump();
    expect(find.text('later'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('later'), findsNothing);
    expect(consumed, isNull);

    unread.remove('mail-3');
    await tester.pump(const Duration(milliseconds: 25));
    expect(consumed?.id, 'mail-3');
    expect(consumed?.content, 'later');
  });
}
