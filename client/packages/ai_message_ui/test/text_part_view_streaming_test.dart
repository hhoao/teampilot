import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  setUp(clearMessageContentCache);

  testWidgets('complete message compiles immediately on each text change', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: _Harness(initialText: 'one', initialStreaming: false),
      ),
    );
    final afterFirst = messageContentCacheLength;

    final state = tester.state<_HarnessState>(find.byType(_Harness));
    state.update(text: 'two');
    await tester.pump();
    expect(messageContentCacheLength, greaterThan(afterFirst));
  });

  testWidgets('streaming tip throttles compile until window elapses', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: _Harness(initialText: 'a', initialStreaming: true),
      ),
    );
    final baseline = messageContentCacheLength;

    final state = tester.state<_HarnessState>(find.byType(_Harness));
    state.update(text: 'ab');
    await tester.pump();
    state.update(text: 'abc');
    await tester.pump();
    expect(messageContentCacheLength, baseline);

    await tester.pump(AiTextPartView.streamingCompileThrottle);
    expect(messageContentCacheLength, greaterThan(baseline));
  });

  testWidgets('leaving streaming flushes pending text immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: _Harness(initialText: 'a', initialStreaming: true),
      ),
    );
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    state.update(text: 'ab');
    await tester.pump();
    final mid = messageContentCacheLength;

    state.update(text: 'abc', streaming: false);
    await tester.pump();
    expect(messageContentCacheLength, greaterThan(mid));
  });
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.initialText,
    required this.initialStreaming,
  });

  final String initialText;
  final bool initialStreaming;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late String _text = widget.initialText;
  late bool _streaming = widget.initialStreaming;

  void update({String? text, bool? streaming}) {
    setState(() {
      if (text != null) _text = text;
      if (streaming != null) _streaming = streaming;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        extensions: [AiMessageTheme.test()],
      ),
      child: Scaffold(
        body: AiMessageStreamingScope(
          streaming: _streaming,
          child: AiTextPartView(text: _text),
        ),
      ),
    );
  }
}
