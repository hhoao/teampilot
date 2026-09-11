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
}
