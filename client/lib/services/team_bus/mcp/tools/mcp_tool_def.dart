import 'teammate_bus_tool_name.dart';

/// Typed MCP tool advertisement (maps to `tools/list` entries).
class McpToolDef {
  const McpToolDef({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final TeammateBusToolName name;
  final String description;
  final Map<String, Object?> inputSchema;

  Map<String, Object?> toJson() => {
        'name': name.value,
        'description': description,
        'inputSchema': inputSchema,
      };
}
