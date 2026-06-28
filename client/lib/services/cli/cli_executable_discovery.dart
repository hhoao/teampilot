import '../../models/team_config.dart';
import 'cli_tool_locator.dart';
import 'registry/capabilities/executable_resolver_capability.dart';
import 'registry/cli_tool_registry.dart';
import 'remote_cli_locator.dart';

/// Locates CLI executables on the local machine or over SSH using registry
/// metadata — no per-CLI special cases in bootstrap.
class CliExecutableDiscovery {
  CliExecutableDiscovery({CliToolRegistry? registry})
    : _registry = registry ?? CliToolRegistry.builtIn();

  final CliToolRegistry _registry;

  Iterable<CliTool> get _localDiscoverable => _registry.launchable
      .map((definition) => definition.id)
      .where(
        (cli) => _registry.capability<ExecutableResolverCapability>(cli) != null,
      );

  Iterable<CliTool> get _remoteDiscoverable => _localDiscoverable.where(
    (cli) => _registry.capability<RemoteCliLocatorCapability>(cli) != null,
  );

  Future<Map<CliTool, String>> locateLocal({
    ProcessRunner runner = cliToolDefaultProcessRun,
  }) async {
    final located = <CliTool, String>{};
    final discoveries = await Future.wait([
      for (final cli in _localDiscoverable)
        () async {
          final resolver =
              _registry.capability<ExecutableResolverCapability>(cli)!;
          final path = await CliToolLocator(
            resolver.defaultExecutableName,
          ).locate(runner: runner);
          if (path == null || path.isEmpty) return null;
          return MapEntry(cli, path);
        }(),
    ]);
    for (final entry in discoveries) {
      if (entry != null) located[entry.key] = entry.value;
    }
    return located;
  }

  Future<Map<CliTool, String>> locateRemote({
    required SshCommandRunner run,
  }) async {
    final locator = RemoteCliLocator(registry: _registry);
    final located = <CliTool, String>{};
    for (final cli in _remoteDiscoverable) {
      final path = await locator.resolve(cli: cli, run: run);
      if (path != null && path.isNotEmpty) {
        located[cli] = path;
      }
    }
    return located;
  }

  Future<String?> locateRemoteCli({
    required CliTool cli,
    required SshCommandRunner run,
  }) {
    return RemoteCliLocator(registry: _registry).resolve(cli: cli, run: run);
  }
}
