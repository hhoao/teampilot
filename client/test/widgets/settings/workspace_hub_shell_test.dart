import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/settings/workspace_hub_shell.dart';

void main() {
  testWidgets('split shell animates body when a bodyAnimationKey is provided', (
    tester,
  ) async {
    const animationKey = ValueKey('body-animation-layout');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 500,
            child: WorkspaceSplitShell(
              bodyAnimationKey: animationKey,
              nav: const SizedBox(child: Text('Nav')),
              body: const Text('Body'),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 260));

    expect(
      find.ancestor(
        of: find.text('Body'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Animate && widget.key == animationKey,
        ),
      ),
      findsOneWidget,
    );

  });

  testWidgets('split shell recreates body animation when the key changes', (
    tester,
  ) async {
    Future<void> pumpSplitBody(String section) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 500,
              child: WorkspaceSplitShell(
                bodyAnimationKey: ValueKey('body-animation-$section'),
                nav: const SizedBox(child: Text('Nav')),
                body: Text('Body $section'),
              ),
            ),
          ),
        ),
      );
    }

    await pumpSplitBody('layout');
    await tester.pump(const Duration(milliseconds: 260));

    await pumpSplitBody('llm');
    await tester.pump(const Duration(milliseconds: 260));

    expect(
      find.ancestor(
        of: find.text('Body llm'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Animate &&
              widget.key == const ValueKey('body-animation-llm'),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Body layout'), findsNothing);
  });

  testWidgets('animated nav entries fade-slide into their final position', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 240,
            child: WorkspaceHubNavList(
              animateEntries: true,
              entries: [
                WorkspaceHubEntry(
                  key: const ValueKey('layout-entry'),
                  title: 'Layout',
                  icon: Icons.dashboard_customize_outlined,
                  onTap: () {},
                ),
                WorkspaceHubEntry(
                  title: 'Models',
                  icon: Icons.memory_outlined,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Animate), findsNWidgets(2));
    expect(find.byKey(const ValueKey('layout-entry')), findsOneWidget);
  });
}
