import '../jsonrpc.dart';
import '../toolkit/mcp_schema.dart';
import '../toolkit/teammate_bus_tool.dart';
import '../toolkit/teammate_bus_tool_call.dart';
import '../toolkit/teammate_bus_tool_context.dart';
import '../toolkit/teammate_bus_tool_name.dart';

final class ListArtifactsTool extends TeammateBusTool {
  const ListArtifactsTool();

  @override
  TeammateBusToolName get name => TeammateBusToolName.listArtifacts;

  @override
  bool isEnabled(TeammateBusToolContext ctx) => ctx.artifacts != null;

  @override
  String get description =>
      'List artifacts currently published on the bus (name, publisher, '
      'size). Use a name with fetch_artifact to pull it to your machine.';

  @override
  Map<String, Object?> get inputSchema => McpSchema.object();

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async {
    final unavailable = call.artifactsUnavailable();
    if (unavailable != null) return unavailable;

    final handles = call.artifacts.list();
    if (handles.isEmpty) {
      return call.ok('No artifacts published.');
    }
    final lines = <String>['Artifacts (${handles.length}):'];
    for (final handle in handles) {
      lines.add(
        '- ${handle.name} (by ${handle.publisherMemberId}, ${handle.sizeBytes} bytes)',
      );
    }
    return call.ok(lines.join('\n'));
  }
}
