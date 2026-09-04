import 'package:path/path.dart' as p;

import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../cli/cli_executable_discovery.dart';
import '../cli/cli_tool_locator.dart';
import '../cli/registry/capabilities/cli_executable_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../host/host_one_shot_runner.dart';
import '../remote/remote_cli_readiness.dart';
import 'models/team_target_probe.dart';

/// Read-only CLI and target probe used by team generation validation.
final class RuntimeTeamTargetProbeRunner implements TeamTargetProbeRunner {
  RuntimeTeamTargetProbeRunner({
    required CliToolRegistry registry,
    required Future<RuntimeTarget?> Function(String targetId) targetResolver,
    CliExecutableDiscovery? localDiscovery,
    RemoteCliReadinessService? remoteReadiness,
    ProcessRunner? localProcessRunner,
    HostOneShotRunner Function(RuntimeTarget target)? wslRunnerFactory,
  }) : _registry = registry,
       _targetResolver = targetResolver,
       _localDiscovery =
           localDiscovery ?? CliExecutableDiscovery(registry: registry),
       _remoteReadiness = remoteReadiness,
       _localProcessRunner = localProcessRunner ?? cliToolDefaultProcessRun,
       _wslRunnerFactory =
           wslRunnerFactory ??
           ((target) => WslHostOneShotRunner(distro: target.wslDistro));

  final CliToolRegistry _registry;
  final Future<RuntimeTarget?> Function(String targetId) _targetResolver;
  final CliExecutableDiscovery _localDiscovery;
  final RemoteCliReadinessService? _remoteReadiness;
  final ProcessRunner _localProcessRunner;
  final HostOneShotRunner Function(RuntimeTarget target) _wslRunnerFactory;

  @override
  Future<TeamTargetProbe> probe({
    required Workspace workspace,
    required String targetId,
    required Set<String> cliValues,
  }) async {
    final target = await _targetResolver(targetId);
    if (target == null) {
      return _unavailable(targetId, 'target_not_found');
    }

    final cliTools = <CliTool>{};
    for (final value in cliValues) {
      final cli = CliTool.values.firstWhere(
        (candidate) => candidate.value == value,
        orElse: () => CliTool.claude,
      );
      if (_registry.tryGet(cli) != null && cli.value == value) {
        cliTools.add(cli);
      }
    }
    if (cliTools.isEmpty) {
      return TeamTargetProbe(
        targetId: targetId,
        status: TeamTargetProbeStatus.available,
        folderIds: const [],
        cliProbes: const [],
        transportKind: target.kind.name,
      );
    }

    if (target.kind == RuntimeKind.local) {
      return _probeLocal(target, cliTools);
    }
    if (target.kind == RuntimeKind.wsl) {
      return _probeWsl(target, cliTools);
    }
    if (usesSshTransport(target.kind)) {
      return _probeRemote(target, cliTools);
    }
    return _unavailable(targetId, 'target_kind_not_supported');
  }

  Future<TeamTargetProbe> _probeLocal(
    RuntimeTarget target,
    Set<CliTool> cliTools,
  ) async {
    final probes = <TeamTargetCliProbe>[];
    for (final cli in cliTools) {
      final path = await _localDiscovery.locateLocalCli(
        cli,
        runner: _localProcessRunner,
      );
      if (path == null) {
        probes.add(
          TeamTargetCliProbe.bounded(
            cliValue: cli.value,
            available: false,
            diagnostic: 'cli_not_found',
          ),
        );
        continue;
      }
      var version = '';
      var diagnostic = '';
      try {
        final result = await _localProcessRunner(path, const ['--version']);
        if (result.exitCode == 0) {
          version = _firstLine(result.stdout);
        } else {
          diagnostic = 'version_probe_failed';
        }
      } on Object {
        diagnostic = 'version_probe_failed';
      }
      probes.add(
        TeamTargetCliProbe.bounded(
          cliValue: cli.value,
          available: true,
          version: version,
          executableBasename: p.basename(path),
          diagnostic: diagnostic,
        ),
      );
    }
    return TeamTargetProbe(
      targetId: target.id,
      status: TeamTargetProbeStatus.available,
      folderIds: const [],
      cliProbes: probes,
      transportKind: target.kind.name,
    );
  }

  Future<TeamTargetProbe> _probeWsl(
    RuntimeTarget target,
    Set<CliTool> cliTools,
  ) async {
    final host = _wslRunnerFactory(target);
    final probes = <TeamTargetCliProbe>[];
    for (final cli in cliTools) {
      final capability = _registry.capability<CliExecutableCapability>(cli);
      if (capability == null) continue;
      final result = await host.run(
        HostRunRequest(
          executable: capability.defaultExecutableName,
          arguments: const ['--version'],
        ),
      );
      probes.add(
        TeamTargetCliProbe.bounded(
          cliValue: cli.value,
          available: result.succeeded,
          version: result.succeeded ? _firstLine(result.stdout) : '',
          executableBasename: capability.defaultExecutableName,
          diagnostic: result.succeeded ? '' : 'version_probe_failed',
        ),
      );
    }
    return TeamTargetProbe(
      targetId: target.id,
      status: TeamTargetProbeStatus.available,
      folderIds: const [],
      cliProbes: probes,
      transportKind: target.kind.name,
    );
  }

  Future<TeamTargetProbe> _probeRemote(
    RuntimeTarget target,
    Set<CliTool> cliTools,
  ) async {
    final readiness = _remoteReadiness;
    if (readiness == null) {
      return _unavailable(target.id, 'remote_probe_unwired');
    }
    final probes = <TeamTargetCliProbe>[];
    for (final cli in cliTools) {
      final result = await readiness.probe(target: target, cli: cli);
      switch (result) {
        case RemoteCliReady(:final path):
          probes.add(
            TeamTargetCliProbe.bounded(
              cliValue: cli.value,
              available: true,
              executableBasename: p.basename(path),
            ),
          );
        case RemoteCliMissing():
          probes.add(
            TeamTargetCliProbe.bounded(
              cliValue: cli.value,
              available: false,
              diagnostic: 'cli_not_found',
            ),
          );
        case RemoteCliFailed(:final message):
          probes.add(
            TeamTargetCliProbe.bounded(
              cliValue: cli.value,
              available: false,
              diagnostic: message,
            ),
          );
        case RemoteCliProbing():
        case RemoteCliInstalling():
          probes.add(
            TeamTargetCliProbe.bounded(
              cliValue: cli.value,
              available: false,
              diagnostic: 'cli_probe_incomplete',
            ),
          );
      }
    }
    return TeamTargetProbe(
      targetId: target.id,
      status: TeamTargetProbeStatus.available,
      folderIds: const [],
      cliProbes: probes,
      transportKind: target.kind.name,
    );
  }

  TeamTargetProbe _unavailable(String targetId, String diagnostic) =>
      TeamTargetProbe(
        targetId: targetId,
        status: TeamTargetProbeStatus.unavailable,
        folderIds: const [],
        cliProbes: [
          TeamTargetCliProbe.bounded(
            cliValue: '*',
            available: false,
            diagnostic: diagnostic,
          ),
        ],
      );

  String _firstLine(Object value) {
    final lines = value.toString().trim().split('\n');
    return lines.isEmpty ? '' : lines.first.trim();
  }
}
