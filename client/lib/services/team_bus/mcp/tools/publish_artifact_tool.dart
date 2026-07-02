import 'mcp_schema.dart';
import 'mcp_tool_def.dart';
import 'teammate_bus_tool_name.dart';

abstract final class PublishArtifactTool {
  static const path = 'path';
  static const name = 'name';
  static const kind = 'kind';
  static const overwrite = 'overwrite';

  static final def = McpToolDef(
    name: TeammateBusToolName.publishArtifact,
    description:
        'Publish a file on YOUR machine so a teammate can fetch it (members '
        'do not share a filesystem). Records only a handle (name + path + '
        'size); the file is not copied until someone fetches it. path is an '
        'absolute path on your own machine; name is the logical name '
        'teammates fetch by. Single files only. Fails if name is already '
        'published unless overwrite=true.',
    inputSchema: McpSchema.object(
      properties: {
        path: McpSchema.string,
        name: McpSchema.string,
        kind: McpSchema.stringEnum(['file']),
        overwrite: McpSchema.boolean,
      },
      required: [path, name],
    ),
  );
}
