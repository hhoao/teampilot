class McpServerValidator {
  List<String> validateId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return const ['id required'];
    return const [];
  }

  List<String> validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const ['name required'];
    if (trimmed.contains(' ')) return const ['name must not contain spaces'];
    return const [];
  }

  List<String> validateServer(Map<String, Object?> server) {
    final type = (server['type'] as String?)?.trim().toLowerCase() ?? 'stdio';
    switch (type) {
      case 'stdio':
        if ((server['command'] as String?)?.trim().isNotEmpty != true) {
          return const ['command required for stdio'];
        }
        return const [];
      case 'streamable-http':
      case 'http':
      case 'sse':
        if ((server['url'] as String?)?.trim().isNotEmpty != true) {
          return ['url required for $type'];
        }
        return const [];
      default:
        return ['unsupported type: $type'];
    }
  }

  List<String> validateOptionalUrl(String value, String fieldLabel) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const [];
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return ['$fieldLabel must be a valid URL'];
    }
    return const [];
  }

  List<String> validate(McpServerFields fields) {
    return [
      ...validateId(fields.id),
      ...validateName(fields.name),
      ...validateServer(fields.server),
      ...validateOptionalUrl(fields.homepage, 'homepage'),
      ...validateOptionalUrl(fields.docs, 'docs'),
    ];
  }
}

class McpServerFields {
  const McpServerFields({
    required this.id,
    required this.name,
    required this.server,
    this.homepage = '',
    this.docs = '',
  });

  final String id;
  final String name;
  final Map<String, Object?> server;
  final String homepage;
  final String docs;
}
