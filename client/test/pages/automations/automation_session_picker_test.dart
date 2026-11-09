import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/automations/automation_session_picker.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';

AppSession _session(String id) => AppSession(
  sessionId: id,
  workspaceId: 'ws1',
  display: 'Session $id',
  cli: CliTool.claude,
  createdAt: 1,
);

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: appLocalizationsSupportedLocales,
  home: Scaffold(
    body: CliToolRegistryScope(
      registry: CliToolRegistry.builtIn(),
      child: child,
    ),
  ),
);

void main() {
  testWidgets('returns the tapped session id', (tester) async {
    late Future<String?> result;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              result = showAutomationSessionPicker(
                context,
                sessions: [_session('s1'), _session('s2')],
                selectedId: 's1',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Session s2'));
    await tester.pumpAndSettle();
    expect(await result, 's2');
  });

  testWidgets('empty state shows no selectable rows', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              showAutomationSessionPicker(
                context,
                sessions: const <AppSession>[],
                selectedId: null,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AutomationSessionPickerDialog), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });
}
