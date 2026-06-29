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
}
