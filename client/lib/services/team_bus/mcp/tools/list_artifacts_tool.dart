import 'mcp_schema.dart';
import 'mcp_tool_def.dart';
import 'teammate_bus_tool_name.dart';

abstract final class ListArtifactsTool {
  static final def = McpToolDef(
    name: TeammateBusToolName.listArtifacts,
    description:
        'List artifacts currently published on the bus (name, publisher, '
        'size). Use a name with fetch_artifact to pull it to your machine.',
    inputSchema: McpSchema.object(),
  );
}
