import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/pages/chat/pinned_session_history_column_width.dart';
import 'package:teampilot/theme/app_theme.dart';

void main() {
  ThemeData appTheme() => buildLightTheme();

  testWidgets('parent rebuilds still refresh child when width is unchanged', (
    tester,
  ) async {
    var label = 'a';
    late void Function(void Function()) setLabel;

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: TpTheme(
          data: TpThemeData.fromColorScheme(appTheme().colorScheme, scale: 1),
          child: StatefulBuilder(
            builder: (context, setState) {
              setLabel = setState;
              return PinnedSessionHistoryColumnWidth(
                availableWidth: 1480,
                expandReasoning: false,
                expandTools: false,
                child: Text(label),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('a'), findsOneWidget);
    setLabel(() => label = 'b');
    await tester.pump();
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('width bucket changes still rebuild the themed child', (
    tester,
  ) async {
    var available = 1480.0;
    late void Function(void Function()) setWidth;

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: TpTheme(
          data: TpThemeData.fromColorScheme(appTheme().colorScheme, scale: 1),
          child: StatefulBuilder(
            builder: (context, setState) {
              setWidth = setState;
              return PinnedSessionHistoryColumnWidth(
                availableWidth: available,
                expandReasoning: false,
                expandTools: false,
                child: Builder(
                  builder: (context) {
                    final width = AiMessageTheme.of(context).threadMaxWidth;
                    return Text('w=$width');
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('w=1280.0'), findsOneWidget);

    setWidth(() => available = 1500);
    await tester.pump();
    expect(find.text('w=1280.0'), findsOneWidget);

    setWidth(() => available = 1680);
    await tester.pump();
    // 1680 resolves to 1480 before the 1460 ceiling clamps it.
    expect(find.text('w=1460.0'), findsOneWidget);
  });
}
