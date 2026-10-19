import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/remote/remote_cli_requirements.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/theme/app_theme.dart';

void main() {
  const target = RuntimeTarget(
    id: 'ssh:host-a',
    label: 'Build host',
    kind: RuntimeKind.ssh,
    sshProfileId: 'host-a',
  );

  testWidgets('renders an adapter row from an adapter requirement', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        RemoteCliMachineReadinessPanel(
          fixedRequirements: const [
            RemoteCliRequirement(
              target: target,
              cli: CliTool.claude,
              hostLabel: 'Build host',
              kind: CliBinaryKind.adapter,
            ),
          ],
          selectableTargets: const [target],
          readiness: _FakeReadiness(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Claude Code ACP adapter'), findsOneWidget);
  });
}

Widget _wrap(Widget child) {
  final theme = buildDarkTheme();
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
      child: CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: Scaffold(body: child),
      ),
    ),
  );
}

class _FakeReadiness extends RemoteCliReadinessService {
  _FakeReadiness()
    : super(
        registry: CliToolRegistry.builtIn(),
        sshClientFactory: _ThrowingSshClientFactory(),
        profileById: (_) => null,
        cliPathOverride: (_, __) async => null,
        setCliPathOverride: (_, __, ___) async {},
      );

  @override
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async => RemoteCliMissing(targetId: target.id, cli: cli);
}

class _ThrowingSshClientFactory implements SshClientFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
