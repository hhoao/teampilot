import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/chat_find_bar.dart';
import 'package:teampilot/services/session/chat_transcript_find_controller.dart';

void main() {
  testWidgets('ChatFindBar shows counter and navigates through hits',
      (tester) async {
    final messages = <AiMessage>[
      for (var i = 0; i < 4; i++)
        AiMessage(
          id: 'm-$i',
          role: i.isEven ? AiRole.user : AiRole.assistant,
          parts: [
            AiTextPart(text: i == 3 ? 'fix the alpha bug' : 'alpha note $i'),
          ],
        ),
    ];
    final controller =
        ChatTranscriptFindController(messagesProvider: () => messages);
    addTearDown(controller.dispose);
    final query = TextEditingController();
    final focus = FocusNode();
    addTearDown(query.dispose);
    addTearDown(focus.dispose);
    final navigated = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatFindBar(
            controller: controller,
            queryController: query,
            focusNode: focus,
            onNavigate: (hit) => navigated.add(hit.messageId),
            onClose: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'alpha');
    // Fire the 120ms debounce and rebuild from the notifyListeners.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(controller.hits.length, 4);
    expect(find.text('1/4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    expect(controller.currentIndex, 1);
    expect(find.text('2/4'), findsOneWidget);
    expect(navigated.last, 'm-1');
  });

  testWidgets('ChatFindBar zero-match query shows the no-results label',
      (tester) async {
    final messages = <AiMessage>[
      AiMessage(
        id: 'm-0',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'alpha note')],
      ),
    ];
    final controller =
        ChatTranscriptFindController(messagesProvider: () => messages);
    addTearDown(controller.dispose);
    final query = TextEditingController();
    final focus = FocusNode();
    addTearDown(query.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatFindBar(
            controller: controller,
            queryController: query,
            focusNode: focus,
            onNavigate: (_) {},
            onClose: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'zzz-none');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(controller.hasQuery, isTrue);
    expect(controller.hits, isEmpty);
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Loading conversation…'), findsNothing);
  });

  testWidgets('ChatFindBar tapping a result row syncs the n/N counter',
      (tester) async {
    // Space the matches well beyond the snippet window (lead 48 / trail 96) so
    // each row's snippet is unique, letting the tap target a single row.
    final messages = <AiMessage>[
      AiMessage(
        id: 'm-0',
        role: AiRole.user,
        parts: [AiTextPart(text: '${'0' * 200} alpha zero')],
      ),
      AiMessage(
        id: 'm-1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: '${'1' * 200} alpha one')],
      ),
      AiMessage(
        id: 'm-2',
        role: AiRole.user,
        parts: [AiTextPart(text: '${'2' * 200} alpha two')],
      ),
    ];
    final controller =
        ChatTranscriptFindController(messagesProvider: () => messages);
    addTearDown(controller.dispose);
    final query = TextEditingController();
    final focus = FocusNode();
    addTearDown(query.dispose);
    addTearDown(focus.dispose);
    final navigated = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatFindBar(
            controller: controller,
            queryController: query,
            focusNode: focus,
            onNavigate: (hit) => navigated.add(hit.messageId),
            onClose: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(controller.hits.length, 3);
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.textContaining('alpha one'));
    await tester.pump();

    expect(controller.currentIndex, 1);
    expect(find.text('2/3'), findsOneWidget);
    expect(navigated.last, 'm-1');
  });

  testWidgets('ChatFindBar Escape closes the find bar', (tester) async {
    final controller =
        ChatTranscriptFindController(messagesProvider: () => const []);
    addTearDown(controller.dispose);
    final query = TextEditingController();
    final focus = FocusNode();
    addTearDown(query.dispose);
    addTearDown(focus.dispose);
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatFindBar(
            controller: controller,
            queryController: query,
            focusNode: focus,
            onNavigate: (_) {},
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, isTrue);
  });
}
