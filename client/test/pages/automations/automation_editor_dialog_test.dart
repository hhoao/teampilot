import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/automations/automation_editor_dialog.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';

import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

import '../../support/post_frame_test_harness.dart';

Widget _host({
  required AutomationCubit cubit,
  required Widget child,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: BlocProvider<AutomationCubit>.value(
        value: cubit,
        child: CliToolRegistryScope(
          registry: CliToolRegistry.builtIn(),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('scheduled message editor shows core fields only', (tester) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: AutomationEditorDialog(
          kind: AutomationEditorKind.scheduledMessage,
          workspaceId: 'ws1',
          launchProfileId: LaunchProfileProvisioner.defaultPersonalId,
          sessionId: 'sess-1',
          defaultName: 'Daily ping',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    expect(find.text(l10n.automationsCompactTitle), findsOneWidget);
    expect(find.text(l10n.automationsName), findsOneWidget);
    expect(find.text(l10n.automationsMessage), findsOneWidget);
    expect(find.text(l10n.automationsEnabled), findsOneWidget);
    expect(find.text(l10n.automationsCli), findsNothing);
    expect(find.text(l10n.automationsTargetMember), findsNothing);
  });

  testWidgets('launch prompt editor shows cli and target member fields', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: AutomationEditorDialog(
          workspaceId: 'ws1',
          launchProfileId: LaunchProfileProvisioner.defaultPersonalId,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    expect(find.text(l10n.automationsCreateTitle), findsOneWidget);
    expect(find.text(l10n.automationsCli), findsOneWidget);
    expect(find.text(l10n.automationsTargetMember), findsOneWidget);
  });

  testWidgets('scheduled message editor pre-fills session defaults', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: AutomationEditorDialog(
          kind: AutomationEditorKind.scheduledMessage,
          workspaceId: 'ws1',
          launchProfileId: LaunchProfileProvisioner.defaultPersonalId,
          sessionId: 'sess-1',
          defaultName: 'Daily ping',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.controller?.text, 'Daily ping');
  });
}
