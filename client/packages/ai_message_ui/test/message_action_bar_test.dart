import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final message = AiMessage(
    id: '1',
    role: AiRole.assistant,
    parts: const [AiTextPart(text: 'hello')],
  );

  Finder copyIcon() => find.byIcon(Icons.copy_rounded);

  testWidgets('hidden hover ActionBar mounts no icons yet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.hover,
          ),
        ),
      ),
    );
    expect(copyIcon(), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(tester.getSize(find.byType(AiMessageActionBar)).height, 40);
  });

  testWidgets('always reveal shows lite action icons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.always,
          ),
        ),
      ),
    );
    expect(copyIcon(), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('hover reveal keeps bar height stable', (tester) async {
    Widget bar({required bool forceVisible}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: AiMessageActionBar(
              message: message,
              reveal: AiActionBarReveal.hover,
              forceVisible: forceVisible,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(bar(forceVisible: false));
    final hidden = tester.getSize(find.byType(AiMessageActionBar));
    expect(copyIcon(), findsNothing);

    await tester.pumpWidget(bar(forceVisible: true));
    await tester.pump();
    final shown = tester.getSize(find.byType(AiMessageActionBar));
    expect(shown.height, equals(hidden.height));
    expect(copyIcon(), findsOneWidget);
  });

  testWidgets('listenable hover lazy-mounts then Opacity-toggles', (
    tester,
  ) async {
    final hovered = ValueNotifier(false);
    addTearDown(hovered.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.hover,
            forceVisibleListenable: hovered,
          ),
        ),
      ),
    );
    expect(copyIcon(), findsNothing);

    hovered.value = true;
    await tester.pump();
    expect(copyIcon(), findsOneWidget);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);

    hovered.value = false;
    await tester.pump();
    // Sticky briefly: icons stay, opacity 0.
    expect(copyIcon(), findsOneWidget);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);

    // Delayed unmount after hide.
    await tester.pump(const Duration(milliseconds: 200));
    expect(copyIcon(), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('hover gate disables ActionBar reveal on AiMessageView', (
    tester,
  ) async {
    final hoverEnabled = ValueNotifier(true);
    addTearDown(hoverEnabled.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 200,
              child: AiMessageView(
                message: message,
                actionBarReveal: AiActionBarReveal.hover,
                actionBarHoverEnabled: hoverEnabled,
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(1, 1));
    addTearDown(gesture.removePointer);
    await tester.pump();

    final center = tester.getCenter(find.byType(AiMessageView));
    await gesture.moveTo(center);
    await tester.pumpAndSettle();
    expect(copyIcon(), findsOneWidget);

    // Scroll-suppress: gate off clears hover and delayed-unmounts icons.
    hoverEnabled.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(copyIcon(), findsNothing);

    // Still over the message with gate off — must not remount.
    await gesture.moveTo(center.translate(1, 1));
    await tester.pump();
    expect(copyIcon(), findsNothing);
  });

  testWidgets('fork and the version control fire from their tooltips', (
    tester,
  ) async {
    var forkCalls = 0;
    var previousCalls = 0;
    var nextCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.always,
            onFork: () => forkCalls++,
            forkLabel: 'Fork from here',
            versionIndex: 2,
            versionCount: 3,
            onPreviousVersion: () => previousCalls++,
            onNextVersion: () => nextCalls++,
          ),
        ),
      ),
    );

    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byTooltip('Fork from here'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous version'));
    await tester.tap(find.byTooltip('Next version'));
    await tester.tap(find.byTooltip('Fork from here'));
    expect(previousCalls, 1);
    expect(nextCalls, 1);
    expect(forkCalls, 1);
  });

  testWidgets('a single checkpoint shows no version control', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.always,
            onFork: () {},
            versionIndex: 1,
            versionCount: 1,
          ),
        ),
      ),
    );

    expect(find.text('1 / 1'), findsNothing);
    expect(find.byTooltip('Previous version'), findsNothing);
    expect(find.byTooltip('Fork from here'), findsOneWidget);
  });

  testWidgets('a running rewind disables fork and the version control', (
    tester,
  ) async {
    var forkCalls = 0;
    var nextCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.always,
            onFork: () => forkCalls++,
            versionIndex: 1,
            versionCount: 2,
            onNextVersion: () => nextCalls++,
            rewindForkEnabled: false,
          ),
        ),
      ),
    );

    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Next version'));
    await tester.tap(find.byTooltip('Fork from here'));
    expect(nextCalls, 0);
    expect(forkCalls, 0);
  });

  testWidgets('dense bar keeps a compact fixed row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.hover,
            dense: true,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AiMessageActionBar)).height, 26);
    expect(copyIcon(), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.always,
            dense: true,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AiMessageActionBar)).height, 26);
    expect(copyIcon(), findsOneWidget);
  });
}
