import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import '../../registry/capabilities/mcp_capability.dart';

/// Gemini MCP: minimal for this phase — no session-scoped MCP writes (gemini
/// sessions are ACP-driven; native MCP assembly is revisited in Task 8+).
final class GeminiMcpCapability implements McpCapability {
  const GeminiMcpCapability();

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
    String? outputBasename,
  }) async {}

  @override
  Future<void> mergeAppCredentials({
    required Filesystem fs,
    required String appConfigDir,
    required String sessionConfigDir,
    String? fallbackAppConfigDir,
  }) async {}

  /// No-op for the same reason as [write]: gemini writes no MCP config in this
  /// phase, so there is never a stale project-scoped teammate-bus entry to
  /// remove.
  @override
  Future<void> maybeRemoveStaleProjectTeammateBus({
    required Filesystem fs,
    Map<String, Map<String, Object?>>? extraServers,
    required String workingDirectory,
    Iterable<String> additionalDirectories = const [],
  }) async {}
}
