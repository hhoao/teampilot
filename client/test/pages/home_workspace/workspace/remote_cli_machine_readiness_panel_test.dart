import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/install_job/install_job_cancelled_exception.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/install/install_job_registry.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
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

  testWidgets('a failed install renders inline', (tester) async {
    final progressCubit = ProgressActivityCubit(
      historyRecorder: _FakeRecorder(),
    );
    final installRegistry = InstallJobRegistry(progressCubit: progressCubit);
    addTearDown(() async {
      installRegistry.dispose();
      await progressCubit.close();
    });

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
          readiness: _FakeReadiness(failInstall: true),
        ),
        installRegistry: installRegistry,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('install failed'), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
  });

  testWidgets('a cancelled install keeps the previous readiness row', (
    tester,
  ) async {
    final progressCubit = ProgressActivityCubit(
      historyRecorder: _FakeRecorder(),
    );
    final installRegistry = InstallJobRegistry(progressCubit: progressCubit);
    addTearDown(() async {
      installRegistry.dispose();
      await progressCubit.close();
    });

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
          readiness: _FakeReadiness(cancelInstall: true),
        ),
        installRegistry: installRegistry,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('install failed'), findsNothing);
    expect(find.textContaining('not found'), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
  });
}

Widget _wrap(Widget child, {InstallJobRegistry? installRegistry}) {
  final theme = buildDarkTheme();
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: appLocalizationsSupportedLocales,
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
      child: CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: installRegistry == null
            ? Scaffold(body: child)
            : Provider<InstallJobRegistry>.value(
                value: installRegistry,
                child: Scaffold(body: child),
              ),
      ),
    ),
  );
}

class _FakeReadiness extends RemoteCliReadinessService {
  _FakeReadiness({this.failInstall = false, this.cancelInstall = false})
    : super(
        registry: CliToolRegistry.builtIn(),
        sshClientFactory: _ThrowingSshClientFactory(),
        profileById: (_) => null,
        cliPathOverride: (_, __) async => null,
        setCliPathOverride: (_, __, ___) async {},
      );

  final bool failInstall;
  final bool cancelInstall;

  @override
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async => RemoteCliMissing(targetId: target.id, cli: cli);

  @override
  Future<RemoteCliReadiness> install({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
    void Function(CliInstallProgress progress)? onProgress,
  }) async {
    if (cancelInstall) {
      throw const InstallJobCancelledException(
        InstallJobKey(kind: InstallJobKind.cliExecutable, target: 'fake'),
      );
    }
    return failInstall
        ? RemoteCliFailed(
            targetId: target.id,
            cli: cli,
            message: 'install failed',
          )
        : RemoteCliMissing(targetId: target.id, cli: cli);
  }
}

final class _FakeRecorder implements NotificationRecorder {
  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {}
}

class _ThrowingSshClientFactory implements SshClientFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
