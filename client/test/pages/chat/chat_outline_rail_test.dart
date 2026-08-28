import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/chat_outline.dart';
import 'package:teampilot/pages/chat/chat_outline_rail.dart';

List<ChatOutlineEntry> _entries() => const [
  ChatOutlineEntry(id: 'u0', messageIndex: 0, preview: 'first prompt'),
  ChatOutlineEntry(id: 'u1', messageIndex: 2, preview: 'second prompt'),
  ChatOutlineEntry(id: 'u2', messageIndex: 4, preview: 'third prompt'),
];

Widget _harness({
  required List<ChatOutlineEntry> entries,
  required ValueNotifier<String?> activeId,
  required List<String> located,
}) {
  return TpTheme(
    data: TpThemeData.fromColorScheme(
      ColorScheme.fromSeed(seedColor: Colors.blue),
      scale: 1,
    ),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: ChatOutlineRail(
            entries: entries,
            activeId: activeId,
            onLocate: (e) => located.add(e.id),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('tick hit testing maps y to nearest index inside slop', () {
    const size = Size(20, 300);
    expect(
      chatOutlineTickAt(local: const Offset(10, 50), size: size, count: 3),
      0,
    );
    expect(
      chatOutlineTickAt(local: const Offset(10, 150), size: size, count: 3),
      1,
    );
    expect(
      chatOutlineTickAt(local: const Offset(10, 250), size: size, count: 3),
      2,
    );
    expect(
      chatOutlineTickAt(local: const Offset(10, 150), size: size, count: 0),
      isNull,
    );
  });

  testWidgets('empty entries paint nothing', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      _harness(entries: const [], activeId: active, located: []),
    );
    expect(find.byKey(kChatOutlineRailKey), findsNothing);
  });

  testWidgets('click tick locates that entry', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    final located = <String>[];
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: located),
    );
    await tester.tapAt(
      tester.getTopLeft(find.byKey(kChatOutlineRailKey)) + const Offset(10, 50),
    );
    await tester.pump();
    expect(located, ['u0']);
  });

  testWidgets('hover shows preview card; click card locates', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    final located = <String>[];
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: located),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    final hoverAt =
        tester.getTopLeft(find.byKey(kChatOutlineRailKey)) +
        const Offset(10, 150);
    await gesture.addPointer(location: hoverAt);
    await gesture.moveTo(hoverAt);
    await tester.pump();
    expect(find.byKey(kChatOutlinePreviewCardKey), findsOneWidget);
    expect(find.text('second prompt'), findsOneWidget);
    await tester.tap(find.byKey(kChatOutlinePreviewCardKey));
    await tester.pump();
    expect(located, ['u1']);
    expect(find.byKey(kChatOutlinePreviewCardKey), findsNothing);
  });

  testWidgets('ArrowDown then Enter locates the next entry', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    final located = <String>[];
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: located),
    );
    // Tap would locate the center tick; request focus so ArrowDown starts at 0.
    tester
        .widget<Focus>(find.byKey(kChatOutlineRailFocusKey))
        .focusNode!
        .requestFocus();
    await tester.pump();
    expect(
      tester
          .widget<Focus>(find.byKey(kChatOutlineRailFocusKey))
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(located, ['u1']);
  });

  testWidgets('replacing entries without hovered id closes overlay', (
    tester,
  ) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    final located = <String>[];
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: located),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    final hoverAt =
        tester.getTopLeft(find.byKey(kChatOutlineRailKey)) +
        const Offset(10, 50);
    await gesture.addPointer(location: hoverAt);
    await gesture.moveTo(hoverAt);
    await tester.pump();
    expect(find.byKey(kChatOutlinePreviewCardKey), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        entries: const [
          ChatOutlineEntry(id: 'other', messageIndex: 0, preview: 'gone'),
        ],
        activeId: active,
        located: located,
      ),
    );
    await tester.pump();
    expect(find.byKey(kChatOutlinePreviewCardKey), findsNothing);
  });
}
