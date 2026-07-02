import 'mcp_schema.dart';
import 'mcp_tool_def.dart';
import 'teammate_bus_tool_name.dart';

abstract final class FetchArtifactTool {
  static const name = 'name';
  static const destPath = 'destPath';
  static const overwrite = 'overwrite';

  static final def = McpToolDef(
    name: TeammateBusToolName.fetchArtifact,
    description:
        'Pull a published artifact to YOUR machine. name is the published '
        'name; destPath is where it lands on your machine and must be inside '
        'your session inbox (relative paths resolve there). Fails if destPath '
        'already exists unless overwrite=true. Returns the final landing path.',
    inputSchema: McpSchema.object(
      properties: {
        name: McpSchema.string,
        destPath: McpSchema.string,
        overwrite: McpSchema.boolean,
      },
      required: [name, destPath],
    ),
  );
}
