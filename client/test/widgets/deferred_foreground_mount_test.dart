import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/deferred_foreground_mount.dart';

void main() {
  testWidgets('DeferredForegroundMount shows placeholder until next frame', (
    tester,
  ) async {
    var built = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DeferredForegroundMount(
          active: true,
          builder: (_) {
            built++;
            return const Text('ready');
          },
        ),
      ),
    );

    expect(find.text('ready'), findsNothing);
    expect(built, 0);

    await tester.pump();
    await tester.pump();

    expect(find.text('ready'), findsOneWidget);
    expect(built, 1);
  });

  testWidgets('retainWhenInactive keeps child mounted when active goes false', (
    tester,
  ) async {
    var built = 0;
    var active = true;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                TextButton(
                  onPressed: () => setState(() => active = false),
                  child: const Text('deactivate'),
                ),
                Expanded(
                  child: DeferredForegroundMount(
                    active: active,
                    retainWhenInactive: true,
                    builder: (_) {
                      built++;
                      return const Text('ready');
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
    final ready = find.text('ready');

    await tester.tap(find.text('deactivate'));
    await tester.pump();

    expect(ready, findsOneWidget);
  });
}
