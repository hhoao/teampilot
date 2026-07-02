/// Helpers for MCP tool `inputSchema` JSON Schema fragments.
abstract final class McpSchema {
  static Map<String, Object?> object({
    Map<String, Object?> properties = const {},
    List<String> required = const [],
  }) =>
      {
        'type': 'object',
        'additionalProperties': false,
        'properties': properties,
        'required': required,
      };

  static const string = {'type': 'string'};
  static const boolean = {'type': 'boolean'};

  static Map<String, Object?> integer({int? minimum, int? maximum}) => {
        'type': 'integer',
        if (minimum != null) 'minimum': minimum,
        if (maximum != null) 'maximum': maximum,
      };

  static Map<String, Object?> stringEnum(List<String> values) => {
        'type': 'string',
        'enum': values,
      };

  static Map<String, Object?> array({
    required Map<String, Object?> items,
  }) =>
      {
        'type': 'array',
        'items': items,
      };
}
