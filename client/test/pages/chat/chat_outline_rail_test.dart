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
          key: const ValueKey('chat-outline-rail-pane'),
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
  test('tick hit testing maps packed y to nearest index inside slop', () {
    const size = Size(44, 300);
    expect(chatOutlineStride(count: 3), kChatOutlineMinTickGap);
    expect(chatOutlineTickY(index: 0, count: 3), 8);
    expect(chatOutlineTickY(index: 1, count: 3), 24);
    expect(chatOutlineTickY(index: 2, count: 3), 40);
    expect(
      chatOutlineTickAt(local: const Offset(8, 8), size: size, count: 3),
      0,
    );
    expect(
      chatOutlineTickAt(local: const Offset(8, 24), size: size, count: 3),
      1,
    );
    expect(
      chatOutlineTickAt(local: const Offset(8, 40), size: size, count: 3),
      2,
    );
    expect(
      chatOutlineTickAt(local: const Offset(8, 150), size: size, count: 3),
      isNull,
    );
    expect(
      chatOutlineTickAt(local: const Offset(8, 24), size: size, count: 0),
      isNull,
    );
  });

  test('bar length falls off by 6px from the hovered peak', () {
    expect(chatOutlineBarLength(index: 0, peakIndex: null), 18);
    expect(chatOutlineBarLength(index: 0, peakIndex: 0), 36);
    expect(chatOutlineBarLength(index: 1, peakIndex: 0), 30);
    expect(chatOutlineBarLength(index: 2, peakIndex: 0), 24);
    expect(chatOutlineBarLength(index: 3, peakIndex: 0), 18);
    expect(chatOutlineBarLength(index: 4, peakIndex: 0), 12);
    expect(chatOutlineBarLength(index: 5, peakIndex: 0), 8);
    expect(chatOutlineBarLength(index: 1, peakIndex: 1), 36);
    expect(chatOutlineBarLength(index: 0, peakIndex: 1), 30);
    expect(chatOutlineBarLength(index: 2, peakIndex: 1), 30);
  });

  testWidgets('empty entries paint nothing', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      _harness(entries: const [], activeId: active, located: []),
    );
    expect(find.byKey(kChatOutlineRailKey), findsNothing);
  });

  testWidgets('menu is vertically centered in the chat pane', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: []),
    );
    final rail = tester.getRect(find.byKey(kChatOutlineRailKey));
    final pane = tester.getRect(
      find.byKey(const ValueKey('chat-outline-rail-pane')),
    );
    expect(rail.height, kChatOutlineMinTickGap * 3);
    expect(rail.center.dy, closeTo(pane.center.dy, 1));
  });

  testWidgets('click tick locates that entry', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    final located = <String>[];
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: located),
    );
    await tester.tapAt(
      tester.getTopLeft(find.byKey(kChatOutlineRailKey)) + const Offset(8, 8),
    );
    await tester.pump();
    expect(located, ['u0']);
  });

  testWidgets('click hides preview but keeps peak while pointer stays', (
    tester,
  ) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    final located = <String>[];
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: located),
    );
    final hoverAt =
        tester.getTopLeft(find.byKey(kChatOutlineRailKey)) + const Offset(8, 8);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: hoverAt);
    await gesture.moveTo(hoverAt);
    await tester.pump();
    expect(find.byKey(kChatOutlinePreviewCardKey), findsOneWidget);
    await tester.tapAt(hoverAt);
    await tester.pump();
    await tester.pump(kChatOutlineBarAnim);
    expect(located, ['u0']);
    expect(find.byKey(kChatOutlinePreviewCardKey), findsNothing);
    final bars = tester
        .renderObjectList<RenderBox>(find.byType(AnimatedContainer))
        .toList();
    expect(bars, isNotEmpty);
    expect(bars.first.size.width, closeTo(kChatOutlineBarPeak, 0.5));
    expect(
      bars[1].size.width,
      closeTo(kChatOutlineBarPeak - kChatOutlineBarStep, 0.5),
    );
  });

  testWidgets('leaving the rail after click returns bars to idle', (
    tester,
  ) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    final located = <String>[];
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: located),
    );
    final railTopLeft = tester.getTopLeft(find.byKey(kChatOutlineRailKey));
    final hoverAt = railTopLeft + const Offset(8, 8);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: hoverAt);
    await gesture.moveTo(hoverAt);
    await tester.pump();
    await tester.tapAt(hoverAt);
    await tester.pump();
    await gesture.moveTo(railTopLeft + const Offset(200, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(kChatOutlineBarAnim);
    expect(find.byKey(kChatOutlinePreviewCardKey), findsNothing);
    final bars = tester.renderObjectList<RenderBox>(
      find.byType(AnimatedContainer),
    );
    expect(bars, isNotEmpty);
    for (final bar in bars) {
      expect(bar.size.width, closeTo(kChatOutlineBarIdle, 0.5));
    }
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
        const Offset(8, 24);
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
        tester.getTopLeft(find.byKey(kChatOutlineRailKey)) + const Offset(8, 8);
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
