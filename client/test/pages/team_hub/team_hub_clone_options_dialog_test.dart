import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/team_hub/team_hub_clone_options_dialog.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';

DiscoverableTeam _undeclared() => const DiscoverableTeam(
  key: 'o/r/s',
  name: 'S',
  description: '',
  category: 'AI',
  updatedAt: 1,
);

DiscoverableTeam _declared() => const DiscoverableTeam(
  key: 'o/r/s',
  name: 'S',
  description: '',
  category: 'AI',
  updatedAt: 1,
  cli: CliTool.codex,
  teamMode: TeamMode.mixed,
);

Future<void> _pumpHost(
  WidgetTester tester, {
  required Widget home,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    CliToolRegistryScope(
      registry: CliToolRegistry.builtIn(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'resolveTeamHubCloneOptions returns effective values without dialog '
    'when both fields are declared',
    (tester) async {
      TeamHubCloneOptions? result;
      await _pumpHost(
        tester,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await resolveTeamHubCloneOptions(context, _declared());
            },
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.teamMode, TeamMode.mixed);
      expect(result!.cli, CliTool.codex);
      expect(find.text('Clone options'), findsNothing);
    },
  );

  testWidgets('dialog confirm returns selected mode and cli', (tester) async {
    TeamHubCloneOptions? result;
    await _pumpHost(
      tester,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await resolveTeamHubCloneOptions(context, _undeclared());
          },
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Team mode'), findsOneWidget);
    expect(find.text('CLI backend'), findsOneWidget);

    await tester.tap(find.text('Mixed (cross-CLI bus)'));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.teamMode, TeamMode.mixed);
    expect(result!.cli, CliTool.claude);
  });

  testWidgets('dialog cancel returns null', (tester) async {
    TeamHubCloneOptions? result;
    await _pumpHost(
      tester,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await resolveTeamHubCloneOptions(context, _undeclared());
          },
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
