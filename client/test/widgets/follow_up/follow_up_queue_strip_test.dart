import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/follow_up/follow_up_queue.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/follow_up/follow_up_queue_strip.dart';

Widget _host(Widget child, {Locale locale = const Locale('en')}) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(body: child),
    ),
  );
}

FollowUpQueueStrip _strip({
  required FollowUpQueue queue,
  VoidCallback? onResume,
  ValueChanged<String>? onDelete,
  void Function(String id, String content)? onEdit,
  ValueChanged<String>? onMoveUp,
}) {
  return FollowUpQueueStrip(
    queue: queue,
    onResume: onResume,
    onDelete: onDelete ?? (_) {},
    onEdit: onEdit ?? (_, __) {},
    onMoveUp: onMoveUp ?? (_) {},
  );
}

void main() {
  testWidgets('hides when queue is empty', (tester) async {
    await tester.pumpWidget(
      _host(_strip(queue: const FollowUpQueue())),
    );
    expect(find.byKey(kSessionFollowUpQueueStripKey), findsNothing);
  });

  testWidgets('shows count and resume when paused', (tester) async {
    var resumed = false;
    await tester.pumpWidget(
      _host(
        _strip(
          queue: const FollowUpQueue(
            items: [FollowUpQueuedMessage(id: '1', content: 'hello')],
            drain: FollowUpDrainMode.paused,
          ),
          onResume: () => resumed = true,
        ),
      ),
    );

    expect(find.textContaining('Queued'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    await tester.tap(find.byTooltip('Resume'));
    await tester.pump();
    expect(resumed, isTrue);
  });

  testWidgets('resume tooltip uses zh locale', (tester) async {
    await tester.pumpWidget(
      _host(
        _strip(
          queue: const FollowUpQueue(
            items: [FollowUpQueuedMessage(id: '1', content: '你好')],
            drain: FollowUpDrainMode.paused,
          ),
          onResume: () {},
        ),
        locale: const Locale('zh'),
      ),
    );

    expect(find.textContaining('排队中'), findsOneWidget);
    expect(find.byTooltip('继续队列'), findsOneWidget);
  });

  testWidgets('no resume when drain is armed', (tester) async {
    await tester.pumpWidget(
      _host(
        _strip(
          queue: const FollowUpQueue(
            items: [FollowUpQueuedMessage(id: '1', content: 'hello')],
            drain: FollowUpDrainMode.armed,
          ),
          onResume: () {},
        ),
      ),
    );

    expect(find.byTooltip('Resume'), findsNothing);
  });

  testWidgets('delete invokes onDelete', (tester) async {
    String? deletedId;
    await tester.pumpWidget(
      _host(
        _strip(
          queue: const FollowUpQueue(
            items: [FollowUpQueuedMessage(id: 'msg-1', content: 'drop me')],
          ),
          onDelete: (id) => deletedId = id,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Delete'));
    await tester.pump();
    expect(deletedId, 'msg-1');
  });

  testWidgets('move up invokes onMoveUp', (tester) async {
    String? movedId;
    await tester.pumpWidget(
      _host(
        _strip(
          queue: const FollowUpQueue(
            items: [
              FollowUpQueuedMessage(id: 'first', content: 'a'),
              FollowUpQueuedMessage(id: 'second', content: 'b'),
            ],
          ),
          onMoveUp: (id) => movedId = id,
        ),
      ),
    );

    final moveButtons = find.byTooltip('Move up');
    expect(moveButtons, findsNWidgets(2));
    await tester.tap(moveButtons.at(1));
    await tester.pump();
    expect(movedId, 'second');
  });

  testWidgets('edit submits updated content', (tester) async {
    String? editedId;
    String? editedContent;
    await tester.pumpWidget(
      _host(
        _strip(
          queue: const FollowUpQueue(
            items: [FollowUpQueuedMessage(id: 'edit-1', content: 'old')],
          ),
          onEdit: (id, content) {
            editedId = id;
            editedContent = content;
          },
        ),
      ),
    );

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'new text');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(editedId, 'edit-1');
    expect(editedContent, 'new text');
  });

  testWidgets('edit cancel restores original content', (tester) async {
    var edited = false;
    await tester.pumpWidget(
      _host(
        _strip(
          queue: const FollowUpQueue(
            items: [FollowUpQueuedMessage(id: 'edit-1', content: 'keep me')],
          ),
          onEdit: (_, __) => edited = true,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'changed');
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(edited, isFalse);
    expect(find.text('keep me'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('collapse hides item rows', (tester) async {
    await tester.pumpWidget(
      _host(
        _strip(
          queue: const FollowUpQueue(
            items: [FollowUpQueuedMessage(id: '1', content: 'hidden row')],
          ),
        ),
      ),
    );

    expect(find.text('hidden row'), findsOneWidget);
    await tester.tap(find.textContaining('Queued'));
    await tester.pumpAndSettle();
    expect(find.text('hidden row'), findsNothing);
  });
}
