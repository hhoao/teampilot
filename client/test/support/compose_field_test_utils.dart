import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The compose field is an [ExtendedTextField] (inline widget chips), so
/// `tester.enterText(find.byType(TextField))` does not find it. Set the
/// controller value directly and focus the field instead.
ExtendedTextField composeFieldWidget(WidgetTester tester) =>
    tester.widget<ExtendedTextField>(find.byType(ExtendedTextField).first);

Future<void> enterComposeText(WidgetTester tester, String text) async {
  final field = composeFieldWidget(tester);
  field.focusNode?.requestFocus();
  await tester.pump();
  field.controller!.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  await tester.pump();
  // Focus after the value change too: the inline field can drop the pending
  // focus request while rebuilding its special-text spans.
  field.focusNode?.requestFocus();
  await tester.pump();
}
