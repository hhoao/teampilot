import '../../cubits/session_preferences_cubit.dart';
import '../../models/cli_binary_kind.dart';
import '../../models/team_config.dart';

/// Returns located entry counts for boot logging.
Future<({int cliCount, int adapterCount, int toolchainCount})>
runLocalCliDiscovery({
  required SessionPreferencesCubit cubit,
  required Future<Map<CliTool, String>> Function() locateCli,
  required Future<Map<CliTool, String>> Function() locateAdapters,
  required Future<Map<String, String>> Function() locateToolchains,
  required Future<String?> Function(String path) probeInstalled,
}) async {
  final cliPaths = await locateCli();
  final acpPaths = await locateAdapters();
  final toolchainPaths = await locateToolchains();
  cubit.mergeLocatedExecutables(cliPaths);
  cubit.mergeLocatedAcpAdapters(acpPaths);
  cubit.mergeLocatedToolchains(toolchainPaths);

  Future<void> probe(CliTool cli, CliBinaryKind kind, String path) async {
    final version = await probeInstalled(path);
    cubit.mergeBinaryVersion(cli: cli, kind: kind, installed: version);
  }

  for (final e in cliPaths.entries) {
    await probe(e.key, CliBinaryKind.cli, e.value);
  }
  for (final e in acpPaths.entries) {
    await probe(e.key, CliBinaryKind.adapter, e.value);
  }

  return (
    cliCount: cliPaths.length,
    adapterCount: acpPaths.length,
    toolchainCount: toolchainPaths.length,
  );
}
