import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/deferred_mount_shell.dart';

void main() {
  testWidgets('DeferredMountAfter mounts immediately under FLUTTER_TEST', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeferredMountAfter(
            delay: Duration(seconds: 10),
            child: Text('loaded'),
          ),
        ),
      ),
    );

    expect(find.text('loaded'), findsOneWidget);
  });
}
