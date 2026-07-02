import '../../artifacts/artifact_exceptions.dart';
import '../jsonrpc.dart';
import '../toolkit/mcp_schema.dart';
import '../toolkit/teammate_bus_tool.dart';
import '../toolkit/teammate_bus_tool_call.dart';
import '../toolkit/teammate_bus_tool_context.dart';
import '../toolkit/teammate_bus_tool_name.dart';

final class FetchArtifactTool extends TeammateBusTool {
  const FetchArtifactTool();

  static const nameKey = 'name';
  static const destPathKey = 'destPath';
  static const overwriteKey = 'overwrite';

  @override
  TeammateBusToolName get name => TeammateBusToolName.fetchArtifact;

  @override
  bool isEnabled(TeammateBusToolContext ctx) => ctx.artifacts != null;

  @override
  String get description =>
      'Pull a published artifact to YOUR machine. name is the published '
      'name; destPath is where it lands on your machine and must be inside '
      'your session inbox (relative paths resolve there). Fails if destPath '
      'already exists unless overwrite=true. Returns the final landing path.';

  @override
  Map<String, Object?> get inputSchema => McpSchema.object(
        properties: {
          nameKey: McpSchema.string,
          destPathKey: McpSchema.string,
          overwriteKey: McpSchema.boolean,
        },
        required: [nameKey, destPathKey],
      );

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async {
    final unavailable = call.artifactsUnavailable();
    if (unavailable != null) return unavailable;

    final name = call.argString(FetchArtifactTool.nameKey)?.trim() ?? '';
    final destPath = call.argString(FetchArtifactTool.destPathKey)?.trim() ?? '';
    if (name.isEmpty || destPath.isEmpty) {
      return call.toolError(
        'fetch_artifact requires a non-empty "name" and "destPath".',
      );
    }
    final overwrite =
        call.argBool(FetchArtifactTool.overwriteKey, defaultValue: false);
    try {
      final result = await call.artifacts.fetch(
        fetcherMemberId: call.memberId,
        name: name,
        destPath: destPath,
        overwrite: overwrite,
      );
      return call.ok(
        'Fetched "${result.name}" (${result.sizeBytes} bytes) to '
        '${result.finalPath}.',
      );
    } on ArtifactException catch (error) {
      return call.toolError(error.toString());
    }
  }
}
