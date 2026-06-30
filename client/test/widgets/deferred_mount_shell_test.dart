import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/deferred_mount_shell.dart';

void main() {
  testWidgets('DeferredMountShell shows child immediately in tests', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeferredMountShell(
          child: Text('ready'),
        ),
      ),
    );

    expect(find.text('ready'), findsOneWidget);
  });
}
