import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_message_edit_panel.dart';

const _field = ValueKey('chat-edit-sheet-field');
const _send = ValueKey('chat-edit-sheet-send');
const _cancel = ValueKey('chat-edit-sheet-cancel');
const _close = ValueKey('chat-edit-sheet-close');

Widget _host(
  Future<bool> Function(String text) onSubmit,
  ValueChanged<bool> onResult,
) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            key: const ValueKey('open'),
            onPressed: () async {
              final result = await showChatMessageEditSheet(
                context,
                initialText: 'original text',
                title: 'Edit message',
                cancelLabel: 'Cancel',
                sendLabel: 'Send',
                onSubmit: onSubmit,
              );
              onResult(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('sheet prefills the original text and returns true on success', (tester) async {
    final submitted = <String>[];
    final results = <bool>[];
    await tester.pumpWidget(
      _host((text) async {
        submitted.add(text);
        return true;
      }, results.add),
    );
    await _open(tester);

    expect(find.byKey(_field), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(_field)).controller!.text,
      'original text',
    );

    await tester.enterText(find.byKey(_field), 'edited');
    await tester.tap(find.byKey(_send));
    await _settle(tester);

    expect(submitted, ['edited']);
    expect(results, [isTrue]);
    expect(find.byKey(_field), findsNothing);
  });

  testWidgets('a failed submit keeps the sheet and the draft', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(_host((text) async => false, results.add));
    await _open(tester);

    await tester.enterText(find.byKey(_field), 'edited');
    await tester.tap(find.byKey(_send));
    await _settle(tester);

    expect(find.byKey(_field), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(_field)).controller!.text,
      'edited',
    );
    expect(results, isEmpty);
  });

  testWidgets('cancel returns false and closes the sheet', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(_host((text) async => true, results.add));
    await _open(tester);

    await tester.tap(find.byKey(_cancel));
    await _settle(tester);

    expect(results, [isFalse]);
    expect(find.byKey(_field), findsNothing);
  });

  testWidgets('close icon returns false', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(_host((text) async => true, results.add));
    await _open(tester);

    await tester.tap(find.byKey(_close));
    await _settle(tester);

    expect(results, [isFalse]);
  });

  testWidgets('empty text does not submit', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      _host((text) async {
        submitted.add(text);
        return true;
      }, (_) {}),
    );
    await _open(tester);

    await tester.enterText(find.byKey(_field), '   ');
    await tester.tap(find.byKey(_send));
    await _settle(tester);

    expect(submitted, isEmpty);
    expect(find.byKey(_field), findsOneWidget);
  });
}
