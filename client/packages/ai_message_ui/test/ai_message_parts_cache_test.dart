import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unchanged parts keep their built widget across updates', (
    tester,
  ) async {
    final builds = <String, int>{};
    final registry = AiPartRegistry(
      builders: {
        AiTextPart: (context, part) {
          final text = (part as AiTextPart).text;
          builds[text] = (builds[text] ?? 0) + 1;
          return Text(text);
        },
      },
    );

    Future<void> pump(List<AiMessagePart> parts) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageParts(parts: parts, registry: registry),
        ),
      ),
    );

    await pump(const [
      AiTextPart(text: 'first'),
      AiTextPart(text: 'second'),
      AiTextPart(text: 'third'),
    ]);
    expect(builds, {'first': 1, 'second': 1, 'third': 1});

    // Streaming replaces only the middle part: the other two nodes must be
    // reused (identical widget → the element is not rebuilt).
    await pump(const [
      AiTextPart(text: 'first'),
      AiTextPart(text: 'second!'),
      AiTextPart(text: 'third'),
    ]);
    expect(builds, {'first': 1, 'second': 1, 'third': 1, 'second!': 1});

    // Dropped nodes leave the cache; re-adding one builds it again.
    await pump(const [AiTextPart(text: 'first')]);
    await pump(const [AiTextPart(text: 'first'), AiTextPart(text: 'third')]);
    expect(builds['first'], 1);
    expect(builds['third'], 2);
  });

  testWidgets('chain nodes rebuild when their parts change', (tester) async {
    final registry = AiPartRegistry(
      chainOfThoughtBuilder: (context, parts) => Column(
        children: [
          for (final part in parts)
            if (part case AiReasoningPart(:final text)) Text(text),
        ],
      ),
    );

    Future<void> pump(List<AiMessagePart> parts) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageParts(parts: parts, registry: registry),
        ),
      ),
    );

    await pump(const [
      AiReasoningPart(text: 'think 1'),
      AiReasoningPart(text: 'think 2'),
    ]);
    expect(find.text('think 1'), findsOneWidget);

    await pump([
      const AiReasoningPart(text: 'think 1'),
      const AiReasoningPart(text: 'think 2'),
      const AiReasoningPart(text: 'think 3'),
    ]);
    expect(find.text('think 3'), findsOneWidget);
  });

  testWidgets('re-parsed parts with identical content keep the chain cached', (
    tester,
  ) async {
    AiChainOfThoughtView.debugBuildCount = 0;
    final hostKey = GlobalKey<_RebuildHostState>();

    // Non-const parts: every build yields new instances, which is what the
    // transcript hands in on each streamed chunk.
    await tester.pumpWidget(_RebuildHost(key: hostKey, parts: _chainParts));
    final mounted = AiChainOfThoughtView.debugBuildCount;
    expect(mounted, greaterThan(0), reason: 'chain must mount');

    hostKey.currentState!.rebuild();
    await tester.pump();

    expect(
      AiChainOfThoughtView.debugBuildCount,
      mounted,
      reason: 'unchanged content must hit the node cache',
    );

    AiChainOfThoughtView.debugMissReasons.clear();
    hostKey.currentState!.setReasoning('thinking even harder');
    await tester.pump();

    expect(
      AiChainOfThoughtView.debugBuildCount,
      greaterThan(mounted),
      reason: 'a growing reasoning part must re-render',
    );
    expect(
      AiChainOfThoughtView.debugMissReasons.keys,
      contains('digests'),
      reason: 'the counter must attribute a content change',
    );
  });
  testWidgets('cache stats separate hits from misses', (tester) async {
    aiMessagePartsCacheStats
      ..builds = 0
      ..hits = 0
      ..misses = 0
      ..clears = 0
      ..states = 0;
    final hostKey = GlobalKey<_RebuildHostState>();

    await tester.pumpWidget(_RebuildHost(key: hostKey, parts: _chainParts));
    expect(aiMessagePartsCacheStats.states, 1);
    expect(aiMessagePartsCacheStats.misses, greaterThan(0));

    final missesAfterMount = aiMessagePartsCacheStats.misses;
    hostKey.currentState!.rebuild();
    await tester.pump();

    expect(
      aiMessagePartsCacheStats.hits,
      greaterThan(0),
      reason: 'unchanged nodes must be served from the cache',
    );
    expect(
      aiMessagePartsCacheStats.misses,
      missesAfterMount,
      reason: 'a plain rebuild must not create nodes',
    );
  });
}

List<AiMessagePart> _chainParts([String reasoning = 'thinking']) => [
  AiReasoningPart(text: reasoning),
  const AiToolCallPart(
    toolCallId: 'tool-1',
    toolName: 'Read',
    argsText: '{"path":"a.dart"}',
    result: 'ok',
    status: AiToolCallStatus.complete,
  ),
];

/// Host that rebuilds its subtree the way the transcript does per chunk.
class _RebuildHost extends StatefulWidget {
  const _RebuildHost({required this.parts, super.key});

  final List<AiMessagePart> Function([String]) parts;

  @override
  State<_RebuildHost> createState() => _RebuildHostState();
}

class _RebuildHostState extends State<_RebuildHost> {
  String _reasoning = 'thinking';

  void rebuild() => setState(() {});

  void setReasoning(String value) => setState(() => _reasoning = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(body: AiMessageParts(parts: widget.parts(_reasoning))),
    );
  }
}
