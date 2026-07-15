import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

void main() {
  testWidgets(
    'WorkspacePageCardShell does not hide ListTile ink under colored DecoratedBox',
    (tester) async {
      final messages = <String>[];
      final old = FlutterError.onError;
      FlutterError.onError = (details) {
        messages.add(details.exceptionAsString());
      };
      addTearDown(() => FlutterError.onError = old);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspacePageCardShell(
              child: ListView(
                children: [
                  for (var i = 0; i < 8; i++)
                    ListTile(
                      title: Text('row $i'),
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        messages.where((m) => m.contains('ink splashes may be invisible')),
        isEmpty,
        reason: messages.join('\n---\n'),
      );
    },
  );
}
