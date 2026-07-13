import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/services/run/process_launch_schema.dart';
import 'package:teampilot/widgets/form/app_form.dart';
import 'package:teampilot/widgets/run/launch_config_schema_form.dart';

void main() {
  const base = LaunchConfiguration(
    id: 'api',
    name: 'API',
    type: 'process',
    command: 'echo',
  );

  Future<void> pumpForm(
    WidgetTester tester, {
    required LaunchConfiguration value,
    required ValueChanged<LaunchConfiguration> onChanged,
    List<String> errors = const [],
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppForm(
              child: LaunchConfigSchemaForm(
                value: value,
                onChanged: onChanged,
                schema: ProcessLaunchSchema.configurationSchema,
                errors: errors,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('process form shows Command field', (tester) async {
    await pumpForm(tester, value: base, onChanged: (_) {});

    expect(find.text('Command'), findsOneWidget);
    expect(find.byKey(const Key('launch-config-field-command')), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
  });

  testWidgets('toggling shell updates value via onChanged', (tester) async {
    LaunchConfiguration? latest;
    await pumpForm(
      tester,
      value: base,
      onChanged: (v) => latest = v,
    );

    final shellSwitch = find.byKey(const Key('launch-config-field-shell'));
    expect(shellSwitch, findsOneWidget);

    await tester.tap(shellSwitch);
    await tester.pump();

    expect(latest, isNotNull);
    expect(latest!.shell, isTrue);
  });
}
