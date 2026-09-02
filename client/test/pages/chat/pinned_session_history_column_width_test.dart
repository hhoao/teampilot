import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/pinned_session_history_column_width.dart';

void main() {
  testWidgets('rebuilds builder only when resolved column width changes', (
    tester,
  ) async {
    var builds = 0;
    late void Function(void Function()) setWidth;
    var available = 1480.0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setWidth = setState;
            return PinnedSessionHistoryColumnWidth(
              availableWidth: available,
              builder: (context, columnWidth) {
                builds++;
                return Text('$columnWidth');
              },
            );
          },
        ),
      ),
    );

    expect(builds, 1);
    expect(find.text('1280.0'), findsOneWidget);

    // Same stepped bucket (hold at 1280) — no rebuild.
    setWidth(() => available = 1500);
    await tester.pump();
    expect(builds, 1);

    // Cross into next step — rebuild once.
    setWidth(() => available = 1680);
    await tester.pump();
    expect(builds, 2);
    expect(find.text('1480.0'), findsOneWidget);
  });
}
