import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/workspace_shell.dart';

void main() {
  testWidgets(
    'workspace shell animates child when a childAnimationKey is provided',
    (tester) async {
      const animationKey = ValueKey('chat-workspace-body-session-1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceShell(
              showHeader: false,
              breadcrumb: 'Team / Chat',
              title: 'Chat',
              subtitle: 'Terminal',
              actions: const [],
              childAnimationKey: animationKey,
              child: const Text('Terminal body'),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 320));

      expect(
        find.ancestor(
          of: find.text('Terminal body'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is TweenAnimationBuilder<double> &&
                widget.key == animationKey,
          ),
        ),
        findsOneWidget,
      );

      final animation = tester.widget<TweenAnimationBuilder<double>>(
        find.ancestor(
          of: find.text('Terminal body'),
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
      );
      expect(animation.duration, const Duration(milliseconds: 280));
    },
  );

  testWidgets(
    'workspace shell recreates child animation when the key changes',
    (tester) async {
      Future<void> pumpShell(String sessionId) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WorkspaceShell(
                showHeader: false,
                breadcrumb: 'Team / Chat',
                title: 'Chat',
                subtitle: 'Terminal',
                actions: const [],
                childAnimationKey: ValueKey('chat-workspace-body-$sessionId'),
                child: Text('Terminal body $sessionId'),
              ),
            ),
          ),
        );
      }

      await pumpShell('session-1');
      await tester.pump(const Duration(milliseconds: 320));

      await pumpShell('session-2');
      await tester.pump(const Duration(milliseconds: 320));

      expect(
        find.ancestor(
          of: find.text('Terminal body session-2'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is TweenAnimationBuilder<double> &&
                widget.key == const ValueKey('chat-workspace-body-session-2'),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Terminal body session-1'), findsNothing);
    },
  );
}
