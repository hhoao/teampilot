import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/form/app_form.dart';
import 'package:teampilot/widgets/form/app_form_field.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  AppFormField<String> stringField({
    required String id,
    String? initialValue,
    String? Function(String?)? validator,
    FocusNode? focusNode,
  }) {
    return AppFormField<String>(
      id: id,
      initialValue: initialValue,
      validator: validator,
      focusNode: focusNode,
      builder: (state) {
        return TextField(
          focusNode: state.focusNode,
          onChanged: state.didChange,
          controller: TextEditingController(text: state.value ?? ''),
          decoration: const InputDecoration(),
        );
      },
    );
  }

  group('AppForm value map', () {
    testWidgets('converts dot notation field IDs to nested map', (tester) async {
      final formKey = GlobalKey<AppFormState>();

      await tester.pumpWidget(
        wrap(
          AppForm(
            key: formKey,
            child: Column(
              children: [
                stringField(id: 'user.name', initialValue: 'John'),
                stringField(id: 'user.email', initialValue: 'john@example.com'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(formKey.currentState!.value, {
        'user': {
          'name': 'John',
          'email': 'john@example.com',
        },
      });
    });

    testWidgets('supports nested initialValue', (tester) async {
      final formKey = GlobalKey<AppFormState>();

      await tester.pumpWidget(
        wrap(
          AppForm(
            key: formKey,
            initialValue: const {
              'user': {
                'name': 'Jane',
                'email': 'jane@example.com',
              },
            },
            child: Column(
              children: [
                stringField(id: 'user.name'),
                stringField(id: 'user.email'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(formKey.currentState!.value, {
        'user': {
          'name': 'Jane',
          'email': 'jane@example.com',
        },
      });
    });

    testWidgets('disables nesting when fieldIdSeparator is null', (tester) async {
      final formKey = GlobalKey<AppFormState>();

      await tester.pumpWidget(
        wrap(
          AppForm(
            key: formKey,
            fieldIdSeparator: null,
            child: Column(
              children: [
                stringField(id: 'user.name', initialValue: 'John'),
                stringField(id: 'user.email', initialValue: 'a@b.c'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(formKey.currentState!.value, const {
        'user.name': 'John',
        'user.email': 'a@b.c',
      });
    });
  });

  group('AppForm validation', () {
    testWidgets('validate fails and focuses first invalid field', (tester) async {
      final formKey = GlobalKey<AppFormState>();
      final hostFocus = FocusNode();

      await tester.pumpWidget(
        wrap(
          AppForm(
            key: formKey,
            child: Column(
              children: [
                stringField(
                  id: 'host',
                  focusNode: hostFocus,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'required' : null,
                ),
                stringField(id: 'label', initialValue: 'ok'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(hostFocus.hasFocus, isTrue);
      expect(find.text('required'), findsOneWidget);
    });

    testWidgets('setFieldError surfaces forced error text', (tester) async {
      final formKey = GlobalKey<AppFormState>();

      await tester.pumpWidget(
        wrap(
          AppForm(
            key: formKey,
            child: stringField(id: 'host', initialValue: 'example.com'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      formKey.currentState!.setFieldError('host', 'unreachable');
      await tester.pumpAndSettle();

      expect(find.text('unreachable'), findsOneWidget);
      expect(formKey.currentState!.fields['host']!.hasError, isTrue);
    });

    testWidgets('reset restores initial values', (tester) async {
      final formKey = GlobalKey<AppFormState>();

      await tester.pumpWidget(
        wrap(
          AppForm(
            key: formKey,
            child: stringField(id: 'username', initialValue: 'alice'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      formKey.currentState!.setFieldValue('username', 'bob');
      await tester.pumpAndSettle();
      expect(formKey.currentState!.value['username'], 'bob');

      formKey.currentState!.reset();
      await tester.pumpAndSettle();
      expect(formKey.currentState!.value['username'], 'alice');
    });
  });

  group('AppForm onChanged', () {
    testWidgets('sees updated value after field change', (tester) async {
      final formKey = GlobalKey<AppFormState>();
      var seen = <String, dynamic>{};

      await tester.pumpWidget(
        wrap(
          AppForm(
            key: formKey,
            onChanged: () {
              seen = Map<String, dynamic>.from(formKey.currentState!.value);
            },
            child: AppFormField<String>(
              id: 'username',
              builder: (state) {
                return TextField(
                  onChanged: state.didChange,
                  decoration: const InputDecoration(),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();

      expect(seen['username'], 'hello');
    });
  });
}
