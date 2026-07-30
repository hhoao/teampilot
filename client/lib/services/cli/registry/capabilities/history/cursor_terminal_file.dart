/// Parsed Cursor `projects/{slug}/terminals/*.txt` side file.
final class CursorTerminalFile {
  const CursorTerminalFile({
    this.pid,
    this.cwd,
    required this.command,
    this.title,
    this.status,
    this.startedAt,
    this.runningForMs,
    required this.body,
    this.exitCode,
    this.elapsedMs,
    this.endedAt,
  });

  final String? pid;
  final String? cwd;
  final String command;
  final String? title;
  final String? status;
  final String? startedAt;
  final int? runningForMs;
  final String body;
  final int? exitCode;
  final int? elapsedMs;
  final String? endedAt;
}

CursorTerminalFile? parseCursorTerminalFile(String raw) {
  final sections = _splitOnFenceLines(
    raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
  );
  if (sections.length < 3) return null;

  final header = _parseKeyValueSection(sections[1]);
  final command = _stripQuotes(header['command'] ?? '');
  if (command.trim().isEmpty) return null;

  final body = sections[2].trimRight();

  int? exitCode;
  int? elapsedMs;
  String? endedAt;
  if (sections.length >= 4) {
    final trailer = _parseKeyValueSection(sections[3]);
    exitCode = _parseInt(trailer['exit_code']);
    elapsedMs = _parseInt(trailer['elapsed_ms']);
    endedAt = _stripQuotesOrNull(trailer['ended_at']);
  }

  return CursorTerminalFile(
    pid: _stripQuotesOrNull(header['pid']),
    cwd: _stripQuotesOrNull(header['cwd']),
    command: command,
    title: _stripQuotesOrNull(header['title']),
    status: _stripQuotesOrNull(header['status']),
    startedAt: _stripQuotesOrNull(header['started_at']),
    runningForMs: _parseInt(header['running_for_ms']),
    body: body,
    exitCode: exitCode,
    elapsedMs: elapsedMs,
    endedAt: endedAt,
  );
}

List<String> _splitOnFenceLines(String raw) {
  final sections = <String>[];
  final buffer = StringBuffer();
  for (final line in raw.split('\n')) {
    if (line == '---') {
      sections.add(buffer.toString());
      buffer.clear();
    } else {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(line);
    }
  }
  sections.add(buffer.toString());
  return sections;
}

Map<String, String> _parseKeyValueSection(String section) {
  final values = <String, String>{};
  for (final line in section.split('\n')) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final key = line.substring(0, colon).trim();
    final value = line.substring(colon + 1).trim();
    if (key.isNotEmpty) values[key] = value;
  }
  return values;
}

String _stripQuotes(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2 &&
      ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
          (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

String? _stripQuotesOrNull(String? value) {
  if (value == null) return null;
  final stripped = _stripQuotes(value);
  return stripped.isEmpty ? null : stripped;
}

int? _parseInt(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return int.tryParse(value.trim());
}
