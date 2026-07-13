import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AiMessage _msg(String id, String text) {
  return AiMessage(
    id: id,
    role: AiRole.user,
    parts: [AiTextPart(text: text)],
    status: AiMessageStatus.complete,
  );
}

void main() {
  testWidgets('AiThread shows loadingBuilder when loading', (tester) async {
    final store = ExternalStoreAiThreadRuntime()..setLoading();
    await tester.pumpWidget(
      MaterialApp(
        home: AiThread(
          runtime: store,
          loadingBuilder: (_) => const Text('LOADING'),
          emptyBuilder: (_) => const Text('EMPTY'),
          errorBuilder: (_, msg, retry) => Text('ERR:$msg'),
        ),
      ),
    );
    expect(find.text('LOADING'), findsOneWidget);
  });

  testWidgets('AiThread calls onLoadOlder when scrolled near top', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime();
    final messages = List.generate(
      40,
      (i) => _msg('m$i', 'message line $i\n' * 3),
    );
    store.setMessages(messages);

    var loadOlderCalls = 0;
    final scrollController = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 400,
          child: AiThread(
            runtime: store,
            scrollController: scrollController,
            hasOlder: true,
            isLoadingOlder: false,
            onLoadOlder: () => loadOlderCalls++,
            loadOlderHeaderBuilder: (context, {required isLoadingOlder}) {
              return const SizedBox(height: 24, child: Text('OLDER'));
            },
            loadingBuilder: (_) => const Text('LOADING'),
            emptyBuilder: (_) => const Text('EMPTY'),
            errorBuilder: (_, msg, retry) => Text('ERR:$msg'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(scrollController.hasClients, isTrue);
    expect(scrollController.position.maxScrollExtent, greaterThan(0));

    scrollController.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(loadOlderCalls, greaterThan(0));
  });

  testWidgets('AiThread shows scroll-to-bottom when scrolled up; tap jumps end', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime();
    final messages = List.generate(
      40,
      (i) => _msg('m$i', 'message line $i\n' * 3),
    );
    store.setMessages(messages);
    final scrollController = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 400,
          child: AiThread(
            runtime: store,
            scrollController: scrollController,
            loadingBuilder: (_) => const Text('LOADING'),
            emptyBuilder: (_) => const Text('EMPTY'),
            errorBuilder: (_, msg, retry) => Text('ERR:$msg'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(scrollController.position.maxScrollExtent, greaterThan(0));
    expect(find.byTooltip('Scroll to bottom'), findsNothing);

    scrollController.jumpTo(0);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Scroll to bottom'), findsOneWidget);

    await tester.tap(find.byTooltip('Scroll to bottom'));
    await tester.pumpAndSettle();

    expect(
      scrollController.offset,
      closeTo(scrollController.position.maxScrollExtent, 1),
    );
    expect(find.byTooltip('Scroll to bottom'), findsNothing);
  });
}
