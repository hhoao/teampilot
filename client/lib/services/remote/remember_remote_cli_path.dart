import '../../models/team_config.dart';

/// Caches a resolved remote CLI path into `targets.json` when it differs from
/// the stored per-target override.
Future<void> rememberRemoteCliPathIfNeeded({
  required String targetId,
  required CliTool cli,
  required String resolvedPath,
  required Future<String?> Function(String targetId, String cliValue)
  readCliPathOverride,
  required Future<void> Function(String targetId, String cliValue, String path)
  writeCliPathOverride,
}) async {
  final trimmed = resolvedPath.trim();
  if (trimmed.isEmpty) return;
  final stored = (await readCliPathOverride(targetId, cli.value) ?? '').trim();
  if (trimmed == stored) return;
  await writeCliPathOverride(targetId, cli.value, trimmed);
}
