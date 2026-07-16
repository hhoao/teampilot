import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:ai_message_ui/src/virtual_thread_viewport.dart';
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
    expect(
      scrollController.offset,
      closeTo(scrollController.position.maxScrollExtent, 1),
    );

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
    expect(
      scrollController.offset,
      closeTo(scrollController.position.maxScrollExtent, 1),
    );
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

  testWidgets('AiThread opens at bottom after late layout growth', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime();
    store.setMessages([
      for (var i = 0; i < 12; i++) _msg('m$i', 'line $i'),
    ]);
    final scrollController = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 320,
          child: AiThread(
            runtime: store,
            scrollController: scrollController,
            messageBuilder: (context, message) {
              final part = message.parts.first;
              final text = part is AiTextPart ? part.text : message.id;
              return _GrowingMessageTile(text: text);
            },
            loadingBuilder: (_) => const Text('LOADING'),
            emptyBuilder: (_) => const Text('EMPTY'),
            errorBuilder: (_, msg, retry) => Text('ERR:$msg'),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(scrollController.hasClients, isTrue);
    expect(scrollController.position.maxScrollExtent, greaterThan(0));
    expect(
      scrollController.offset,
      closeTo(scrollController.position.maxScrollExtent, 1),
      reason: 'must stick to bottom after deferred message layout growth',
    );
  });

  testWidgets('AiThread hides list until bottom stick completes', (tester) async {
    final store = ExternalStoreAiThreadRuntime();
    store.setMessages([
      for (var i = 0; i < 30; i++) _msg('m$i', 'message line $i\n' * 4),
    ]);
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

    await tester.pump();
    final first = tester.widget<Opacity>(
      find.byKey(const ValueKey('ai-thread-list-opacity')),
    );
    expect(first.opacity, 0);

    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Opacity>(find.byKey(const ValueKey('ai-thread-list-opacity')))
          .opacity,
      1,
    );
    expect(
      scrollController.offset,
      closeTo(scrollController.position.maxScrollExtent, 1),
    );
  });

  testWidgets('AiThread idle mounts far fewer messages than window', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime();
    store.setMessages(
      List.generate(
        40,
        (i) => AiMessage(
          id: 'm$i',
          role: AiRole.user,
          parts: [AiTextPart(text: 'line $i\n' * 3)],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 400,
          child: AiThread(
            runtime: store,
            loadingBuilder: (_) => const Text('LOADING'),
            emptyBuilder: (_) => const Text('EMPTY'),
            errorBuilder: (_, msg, retry) => Text('ERR:$msg'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AiMessageView), findsWidgets);
    expect(find.byType(AiMessageView).evaluate().length, lessThan(20));
  });

  testWidgets('AiThread load-older prepend preserves scroll anchor', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime();
    final newer = List.generate(
      20,
      (i) => AiMessage(
        id: 'n$i',
        role: AiRole.user,
        parts: [AiTextPart(text: 'newer $i\n' * 4)],
      ),
    );
    store.setMessages(newer);
    final scrollController = ScrollController();
    var hasOlder = true;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              height: 400,
              child: AiThread(
                runtime: store,
                scrollController: scrollController,
                hasOlder: hasOlder,
                isLoadingOlder: false,
                onLoadOlder: () {
                  final older = List.generate(
                    10,
                    (i) => AiMessage(
                      id: 'o$i',
                      role: AiRole.user,
                      parts: [AiTextPart(text: 'older $i\n' * 4)],
                    ),
                  );
                  setState(() {
                    hasOlder = false;
                    store.setMessages([...older, ...newer]);
                  });
                },
                loadOlderHeaderBuilder: (context, {required isLoadingOlder}) {
                  return const SizedBox(height: 24, child: Text('OLDER'));
                },
                loadingBuilder: (_) => const Text('LOADING'),
                emptyBuilder: (_) => const Text('EMPTY'),
                errorBuilder: (_, msg, retry) => Text('ERR:$msg'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Leave bottom stick, stay above the load-older threshold so we can
    // snapshot extent before prepend.
    scrollController.jumpTo(200);
    await tester.pumpAndSettle();
    final beforeExtent = scrollController.position.maxScrollExtent;
    const park = 40.0;
    scrollController.jumpTo(park);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();

    final afterExtent = scrollController.position.maxScrollExtent;
    expect(afterExtent, greaterThan(beforeExtent));
    final delta = afterExtent - beforeExtent;
    // Content that was under [park] stays under the viewport after top prepend.
    // AiThread snapshots pixels/extent immediately before onLoadOlder.
    expect(scrollController.offset, closeTo(park + delta, 5.0));
  });

  testWidgets('AiThread scroll-up rebuilds viewport with stickIntent false', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime();
    store.setMessages([
      for (var i = 0; i < 30; i++) _msg('m$i', 'message line $i\n' * 4),
    ]);
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

    final stuck = tester.widget<VirtualThreadViewport>(
      find.byType(VirtualThreadViewport),
    );
    expect(stuck.stickIntent, isTrue);

    scrollController.jumpTo(0);
    await tester.pump();
    await tester.pumpAndSettle();

    final released = tester.widget<VirtualThreadViewport>(
      find.byType(VirtualThreadViewport),
    );
    expect(released.stickIntent, isFalse);
    expect(find.byTooltip('Scroll to bottom'), findsOneWidget);
  });
}

class _GrowingMessageTile extends StatefulWidget {
  const _GrowingMessageTile({required this.text});

  final String text;

  @override
  State<_GrowingMessageTile> createState() => _GrowingMessageTileState();
}

class _GrowingMessageTileState extends State<_GrowingMessageTile> {
  double _height = 28;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _height = 96);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Text(widget.text),
    );
  }
}
