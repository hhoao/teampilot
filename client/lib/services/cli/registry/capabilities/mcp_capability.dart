import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import '../cli_capability.dart';

/// Writes neutral [McpServerSpec] lists into a CLI's native MCP config files.
abstract interface class McpCapability implements CliCapability {
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
    String? outputBasename,
  });

  /// Merges app-level OAuth credential entries into the session config dir.
  ///
  /// Default: no-op. CLIs that store MCP OAuth tokens on disk override this.
  /// [fallbackAppConfigDir] is used when [appConfigDir] has no OAuth pool (e.g.
  /// tokens saved under the claude app defaults dir).
  Future<void> mergeAppCredentials({
    required Filesystem fs,
    required String appConfigDir,
    required String sessionConfigDir,
    String? fallbackAppConfigDir,
  }) async {}

  /// Drops stale project-scope teammate-bus MCP entries before session-scoped
  /// MCP is written. Default: no-op. CLIs that read a project `.mcp.json`
  /// override this.
  Future<void> maybeRemoveStaleProjectTeammateBus({
    required Filesystem fs,
    Map<String, Map<String, Object?>>? extraServers,
    required String workingDirectory,
    Iterable<String> additionalDirectories = const [],
  }) async {}
}
