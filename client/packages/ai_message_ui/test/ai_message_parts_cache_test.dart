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
}
