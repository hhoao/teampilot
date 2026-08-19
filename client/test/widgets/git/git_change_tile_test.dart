import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
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
    bool selected = false,
    VoidCallback? onSelect,
    VoidCallback? onOpenFile,
    VoidCallback? onStage,
    VoidCallback? onUnstage,
    VoidCallback? onDiscard,
  }) =>
      GitChangeTile(
        change: change,
        depth: 0,
        selected: selected,
        onSelect: onSelect ?? () {},
        onOpenDiff: () {},
        onOpenFile: onOpenFile,
        onStage: onStage ?? () {},
        onUnstage: onUnstage ?? () {},
        onDiscard: onDiscard ?? () {},
      );

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

  testWidgets('unstaged file shows unchecked box; clicking it stages', (
    tester,
  ) async {
    var stagedCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          onStage: () => stagedCalls++,
        )),
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(stagedCalls, 1);
      final cb = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(cb.value, isFalse);
    });
  });

  testWidgets('staged file shows checked box; clicking it unstages', (
    tester,
  ) async {
    var unstagedCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: true,
          ),
          onUnstage: () => unstagedCalls++,
        )),
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(unstagedCalls, 1);
    });
  });

  testWidgets('single click on row selects', (tester) async {
    var selectCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          onSelect: () => selectCalls++,
          onOpenFile: () {},
        )),
      );
      await tester.tap(find.byType(GitChangeTile));
      // Both onTap and onDoubleTap registered → tap fires after the
      // double-tap window expires.
      await tester.pump(const Duration(milliseconds: 400));
      expect(selectCalls, 1);
    });
  });

  testWidgets('double click opens the file', (tester) async {
    var openCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          onOpenFile: () => openCalls++,
        )),
      );
      // Two taps must each come from a fresh pointer (see Task 4
      // hover_double_tap_test.dart); reusing one TestGesture trips a
      // framework gesture-arena assertion unrelated to the tile.
      await tester.tap(find.byType(GitChangeTile), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(GitChangeTile), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(openCalls, 1);
    });
  });

  testWidgets('right-click shows context menu; Open File dispatches', (
    tester,
  ) async {
    var openCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          onOpenFile: () => openCalls++,
        )),
      );
      final center = tester.getCenter(find.byType(GitChangeTile));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // An unstaged (unchecked) row offers to include it in the next commit.
      expect(find.text('Include in Commit'), findsOneWidget);
      await tester.tap(find.text('Open File'));
      await tester.pump();
      expect(openCalls, 1);
    });
  });

  testWidgets(
      'right-click on an unstaged row shows Include; staged row shows Exclude',
      (tester) async {
    await runOnDesktop(tester, () async {
      Future<void> openMenu(GitFileChange change) async {
        await tester.pumpWidget(wrap(tile(change: change)));
        final center = tester.getCenter(find.byType(GitChangeTile));
        final gesture = await tester.startGesture(
          center,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Unstaged row → "Include in Commit" (not a legacy "Stage changes" label).
      await openMenu(
        const GitFileChange(
          path: 'main.dart',
          kind: GitChangeKind.modified,
          staged: false,
        ),
      );
      expect(find.text('Include in Commit'), findsOneWidget);
      expect(find.text('Exclude from Commit'), findsNothing);

      // Staged row → "Exclude from Commit".
      await openMenu(
        const GitFileChange(
          path: 'main.dart',
          kind: GitChangeKind.modified,
          staged: true,
        ),
      );
      expect(find.text('Exclude from Commit'), findsOneWidget);
      expect(find.text('Include in Commit'), findsNothing);
    });
  });

  testWidgets('status badge shown', (tester) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
        )),
      );
      expect(find.text('M'), findsOneWidget);
    });
  });

  testWidgets(
    'selected row keeps secondaryContainer on hover instead of dropping it',
    (tester) async {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      );
      await runOnDesktop(tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(colorScheme: scheme, useMaterial3: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 36,
                child: tile(
                  change: const GitFileChange(
                    path: 'main.dart',
                    kind: GitChangeKind.modified,
                    staged: false,
                  ),
                  selected: true,
                ),
              ),
            ),
          ),
        );
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.byType(GitChangeTile)));
        await tester.pumpAndSettle();
        final box = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(GitChangeTile),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final hovered = (box.decoration! as BoxDecoration).color!;
        expect(
          hovered,
          Color.alphaBlend(
            TpHover.defaultHoverColor(
              tester.element(find.byType(GitChangeTile)),
            ),
            scheme.secondaryContainer,
          ),
        );
      });
    },
  );
}
