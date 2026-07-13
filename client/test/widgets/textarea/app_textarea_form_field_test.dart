import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/form/app_form.dart';
import 'package:teampilot/widgets/textarea/app_textarea_form_field.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  testWidgets('validate fails when short and value maps after valid input', (
    tester,
  ) async {
    final formKey = GlobalKey<AppFormState>();

    await tester.pumpWidget(
      wrap(
        AppForm(
          key: formKey,
          child: Column(
            children: [
              AppTextareaFormField(
                id: 'bio',
                label: const Text('Bio'),
                validator: (v) =>
                    (v == null || v.trim().length < 5) ? 'too short' : null,
              ),
              Builder(
                builder: (context) {
                  return TextButton(
                    onPressed: () {
                      formKey.currentState!.saveAndValidate();
                    },
                    child: const Text('Submit'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('too short'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('too short'), findsNothing);
    expect(formKey.currentState!.value['bio'], 'hello world');
  });
}
