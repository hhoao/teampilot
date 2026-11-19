import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/workspace/running_sessions_scroll.dart';

void main() {
  Future<void> pumpScroll(WidgetTester tester, {int rows = 24}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 200,
              child: RunningSessionsScroll(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rows; i++)
                      SizedBox(height: 46, child: Text('row $i')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Scrollbar scrollbarOf(WidgetTester tester) =>
      tester.widget<Scrollbar>(find.byType(Scrollbar));

  Future<TestGesture> hover(
    WidgetTester tester, {
    required Offset target,
  }) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(target);
    await tester.pump();
    return mouse;
  }

  testWidgets('reveals the thumb when the pointer enters the rows', (
    tester,
  ) async {
    await pumpScroll(tester);
    expect(
      scrollbarOf(tester).thumbVisibility,
      isFalse,
      reason: 'the thumb stays hidden until the pointer enters the rows',
    );

    final mouse = await hover(
      tester,
      target: tester.getCenter(find.byType(RunningSessionsScroll)),
    );
    expect(
      scrollbarOf(tester).thumbVisibility,
      isTrue,
      reason: 'hovering the rows must reveal the thumb',
    );

    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(
      scrollbarOf(tester).thumbVisibility,
      isFalse,
      reason: 'leaving the rows hides the thumb again',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('keeps the thumb visible without hover on touch platforms', (
    tester,
  ) async {
    await pumpScroll(tester);
    expect(
      scrollbarOf(tester).thumbVisibility,
      isTrue,
      reason: 'touch has no hover, so the thumb must not depend on it',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('desktop does not wrap the rows in a second scrollbar', (
    tester,
  ) async {
    await pumpScroll(tester);
    expect(find.byType(Scrollbar), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('rows scroll inside the viewport', (tester) async {
    await pumpScroll(tester);

    final controller = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));

    await tester.drag(
      find.byType(RunningSessionsScroll),
      const Offset(0, -120),
    );
    await tester.pump();
    expect(controller.offset, greaterThan(0));
  });
}
