import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/widgets/git/git_change_tile.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(width: 400, height: 36, child: child),
    ),
  );

  GitChangeTile tile({
    required GitFileChange change,
    VoidCallback? onOpenFile,
  }) =>
      GitChangeTile(
        change: change,
        depth: 0,
        onOpenDiff: () {},
        onStage: () {},
        onUnstage: () {},
        onDiscard: () {},
        onOpenFile: onOpenFile,
      );

  Future<void> hover(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(finder));
    await tester.pump();
  }

  // TpHover renders its desktop (GestureDetector + animated fill) path on a
  // desktop platform. flutter_test defaults to Android, which would render the
  // touch (InkWell) path with no onHoverChanged callback. The override must be
  // reset inside the test body (before flutter_test's invariant check runs), so
  // it is set/reset via try/finally rather than setUp/tearDown.
  Future<void> runOnDesktop(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('hover on unstaged row shows open/discard/stage right-aligned', (
    tester,
  ) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(
          tile(
            change: const GitFileChange(
              path: 'main.dart',
              kind: GitChangeKind.modified,
              staged: false,
            ),
            onOpenFile: () {},
          ),
        ),
      );
      await hover(tester, find.byType(GitChangeTile));

      expect(find.byIcon(Icons.file_open_outlined), findsOneWidget);
      expect(find.byIcon(Icons.undo), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);

      final rowRect = tester.getRect(find.byType(GitChangeTile).first);
      final btnRect = tester.getRect(find.byIcon(Icons.file_open_outlined));
      expect(rowRect.right - btnRect.right, lessThan(16));
    });
  });

  testWidgets('hover on staged row shows open + unstage, no stage', (tester) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(
          tile(
            change: const GitFileChange(
              path: 'main.dart',
              kind: GitChangeKind.modified,
              staged: true,
            ),
            onOpenFile: () {},
          ),
        ),
      );
      await hover(tester, find.byType(GitChangeTile));

      expect(find.byIcon(Icons.file_open_outlined), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
    });
  });

  testWidgets('badge shown when not hovered, no buttons', (tester) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(
          tile(
            change: const GitFileChange(
              path: 'main.dart',
              kind: GitChangeKind.modified,
              staged: false,
            ),
          ),
        ),
      );

      expect(find.text('M'), findsOneWidget);
      expect(find.byIcon(Icons.file_open_outlined), findsNothing);
    });
  });
}
