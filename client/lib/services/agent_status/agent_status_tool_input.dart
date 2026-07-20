/// Derives a short tool-input preview for sticky permission matching.
///
/// Mirrors Orca `deriveToolInputPreview` + `deriveFallbackToolInputPreview`
/// for the common Claude tool names used in permission flows.
String? deriveToolInputPreview(String? toolName, Object? toolInput) {
  if (toolInput is String) {
    final t = toolInput.trim();
    return t.isEmpty ? null : t;
  }
  if (toolInput is! Map) return null;

  final record = <String, Object?>{};
  for (final e in toolInput.entries) {
    record[e.key.toString()] = e.value;
  }

  if (toolName != null && toolName.isNotEmpty) {
    final keys = _keysForTool(toolName);
    for (final key in keys) {
      final value = record[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
  }

  for (final key in _fallbackKeys) {
    final value = record[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

List<String> _keysForTool(String toolName) {
  return switch (toolName) {
    'Bash' || 'bash' || 'Execute' || 'run_shell_command' || 'run_terminal_cmd' =>
      const ['command', 'cmd', 'CommandLine'],
    'Read' || 'read' || 'read_file' || 'view' => const [
      'file_path',
      'filePath',
      'path',
      'AbsolutePath',
    ],
    'Write' ||
    'write' ||
    'write_file' ||
    'Edit' ||
    'edit' ||
    'edit_file' ||
    'MultiEdit' ||
    'Create' ||
    'create' => const ['file_path', 'filePath', 'path', 'TargetFile'],
    'Grep' || 'grep' || 'search_file_content' || 'grep_search' => const [
      'pattern',
      'Query',
      'query',
    ],
    'Glob' || 'glob' || 'find_by_name' => const ['pattern', 'Pattern', 'query'],
    'WebFetch' || 'FetchUrl' || 'web_fetch' || 'read_url_content' => const [
      'url',
      'Url',
    ],
    'WebSearch' || 'web_search' || 'google_web_search' || 'search_web' => const [
      'query',
      'Query',
    ],
    _ => const <String>[],
  };
}

const _fallbackKeys = [
  'command',
  'cmd',
  'code',
  'query',
  'pattern',
  'url',
  'path',
  'file_path',
  'filePath',
  'target',
  'text',
  'action',
  'name',
  'CommandLine',
  'AbsolutePath',
  'TargetFile',
  'Prompt',
];
