import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_trigger_chip_style.dart';

void main() {
  test('buildComposeMirrorLayoutSpans keeps token glyphs transparent', () {
    const style = TextStyle(fontSize: 14, height: 1.5, color: Colors.black);
    final spans = buildComposeMirrorLayoutSpans(
      text: 'use /writing-plans on @src/main.dart',
      baseStyle: style,
    );

    expect(spans.length, 4);
    expect((spans[0] as TextSpan).text, 'use ');
    final slash = spans[1] as TextSpan;
    expect(slash.text, '/writing-plans');
    expect(slash.style?.color, Colors.transparent);
    expect((spans[2] as TextSpan).text, ' on ');
    final at = spans[3] as TextSpan;
    expect(at.text, '@src/main.dart');
    expect(at.style?.color, Colors.transparent);
  });

  test('composeTokenPillWidth never extends past layout token end', () {
    const layoutWidth = 180.0;
    expect(
      composeTokenPillWidth(layoutWidth),
      layoutWidth + composeTokenPillLeftBleed,
    );
  });

  testWidgets('ComposeTriggerStyledMirror paints full slash token label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ComposeTriggerStyledMirror(
              text: 'try /dispatching-parallel-agents now',
              baseStyle: const TextStyle(fontSize: 14, height: 1.5),
              minLines: 1,
              maxLines: 4,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ComposeTriggerStyledMirror), findsOneWidget);
    expect(find.text('/dispatching-parallel-agents'), findsOneWidget);
  });
}
