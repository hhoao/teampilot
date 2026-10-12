import 'package:acpd/acpd.dart' as acpd;

/// Maps extra MCP dicts into ACP servers for `session/new`.
///
/// A `command` entry becomes [acpd.McpServerStdio]. An entry with `type: http`
/// or a `url` and no command becomes [acpd.McpServerHttp]. Headers may be a
/// name-to-value map or a list of `{name, value}` objects. Entries with
/// neither a command nor a url are skipped.
List<acpd.McpServer> acpMcpServersFromExtra(
  Map<String, Map<String, Object?>> extra,
) {
  final servers = <acpd.McpServer>[];
  for (final entry in extra.entries) {
    final spec = entry.value;
    final command = _nonEmptyString(spec['command']);
    final url = _nonEmptyString(spec['url']);
    final type = _nonEmptyString(spec['type'])?.toLowerCase();
    final http = type == 'http' || (url != null && command == null);
    if (http) {
      if (url == null) continue;
      servers.add(
        acpd.McpServerHttp(
          name: entry.key,
          url: url,
          headers: _headers(spec['headers']),
        ),
      );
      continue;
    }
    if (command == null) continue;
    servers.add(
      acpd.McpServerStdio(
        name: entry.key,
        command: command,
        args: _stringList(spec['args']),
      ),
    );
  }
  return servers;
}

String? _nonEmptyString(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item != null) item.toString(),
  ];
}

List<acpd.HttpHeader> _headers(Object? raw) {
  if (raw is Map) {
    final headers = <acpd.HttpHeader>[];
    for (final entry in raw.entries) {
      final name = entry.key.toString();
      final value = entry.value;
      if (name.isEmpty || value == null) continue;
      headers.add(acpd.HttpHeader(name: name, value: value.toString()));
    }
    return headers;
  }
  if (raw is! List) return const [];
  final headers = <acpd.HttpHeader>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final name = item['name']?.toString() ?? '';
    final value = item['value'];
    if (name.isEmpty || value == null) continue;
    headers.add(acpd.HttpHeader(name: name, value: value.toString()));
  }
  return headers;
}
