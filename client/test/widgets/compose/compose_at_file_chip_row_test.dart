import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_at_file_refs.dart';
import 'package:teampilot/widgets/compose/compose_at_file_chip_row.dart';

void main() {
  testWidgets('renders basenames and invokes onOpen', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposeAtFileChipRow(
            refs: const [
              ComposeAtFileRef(
                absolutePath: '/repo/src/a.dart',
                displayName: 'a.dart',
              ),
              ComposeAtFileRef(
                absolutePath: '/tmp/photo.png',
                displayName: 'photo.png',
              ),
            ],
            onOpen: opened.add,
          ),
        ),
      ),
    );

    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);

    await tester.tap(find.text('a.dart'));
    expect(opened, ['/repo/src/a.dart']);
  });

  testWidgets('empty refs builds nothing interactive', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposeAtFileChipRow(refs: const [], onOpen: (_) {}),
        ),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
  });
}
