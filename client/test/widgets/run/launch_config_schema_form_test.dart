import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/services/run/shell_script_launch_schema.dart';
import 'package:teampilot/widgets/dropdown/app_dropdown_field.dart';
import 'package:teampilot/widgets/form/app_form.dart';
import 'package:teampilot/widgets/run/launch_config_schema_form.dart';

void main() {
  LaunchConfiguration shellBase({
    String execute = 'scriptFile',
    String? scriptPath = './run.sh',
    String? scriptText,
  }) {
    return LaunchConfiguration.fromJson(
      ShellScriptLaunchSchema.withDefaults({
        'id': 'sh',
        'name': 'Shell',
        'type': ShellScriptLaunchSchema.typeName,
        'execute': execute,
        if (scriptPath != null) 'scriptPath': scriptPath,
        if (scriptText != null) 'scriptText': scriptText,
      }),
    );
  }

  Future<void> pumpForm(
    WidgetTester tester, {
    required LaunchConfiguration value,
    required ValueChanged<LaunchConfiguration> onChanged,
    required Map<String, Object?> schema,
    List<String> errors = const [],
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppForm(
              child: LaunchConfigSchemaForm(
                value: value,
                onChanged: onChanged,
                schema: schema,
                errors: errors,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shellScript form shows Execute field', (tester) async {
    await pumpForm(
      tester,
      value: shellBase(),
      onChanged: (_) {},
      schema: ShellScriptLaunchSchema.configurationSchema,
    );

    expect(find.text('Execute'), findsOneWidget);
    expect(find.byKey(const Key('launch-config-field-execute')), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
  });

  testWidgets('toggling executeInTerminal checkbox updates value via onChanged', (
    tester,
  ) async {
    LaunchConfiguration? latest;
    await pumpForm(
      tester,
      value: shellBase(),
      onChanged: (v) => latest = v,
      schema: ShellScriptLaunchSchema.configurationSchema,
    );

    final checkbox = find.byKey(
      const Key('launch-config-field-executeInTerminal'),
    );
    expect(checkbox, findsOneWidget);

    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();

    expect(latest, isNotNull);
    expect(latest!.extras['executeInTerminal'], isFalse);
  });

  testWidgets('shellScript form shows execute dropdown and scriptPath', (
    tester,
  ) async {
    await pumpForm(
      tester,
      value: shellBase(),
      onChanged: (_) {},
      schema: ShellScriptLaunchSchema.configurationSchema,
    );

    expect(find.text('Execute'), findsOneWidget);
    expect(find.byKey(const Key('launch-config-field-execute')), findsOneWidget);
    expect(find.text('Script path'), findsOneWidget);
    expect(
      find.byKey(const Key('launch-config-field-scriptPath')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('launch-config-field-scriptText')), findsNothing);
    expect(find.text('Execute in the terminal'), findsOneWidget);
  });

  testWidgets('switching execute to scriptText shows scriptText field', (
    tester,
  ) async {
    LaunchConfiguration? latest = shellBase();
    await pumpForm(
      tester,
      value: latest!,
      onChanged: (v) => latest = v,
      schema: ShellScriptLaunchSchema.configurationSchema,
    );

    expect(find.byKey(const Key('launch-config-field-scriptPath')), findsOneWidget);
    expect(find.byKey(const Key('launch-config-field-scriptText')), findsNothing);

    await tester.tap(find.byKey(const Key('launch-config-field-execute')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Script text').last);
    await tester.pumpAndSettle();

    expect(latest!.extras['execute'], 'scriptText');
    expect(find.byKey(const Key('launch-config-field-scriptPath')), findsNothing);
    expect(
      find.byKey(const Key('launch-config-field-scriptText')),
      findsOneWidget,
    );
    expect(find.byType(AppDropdownField<String>), findsWidgets);
  });
}
