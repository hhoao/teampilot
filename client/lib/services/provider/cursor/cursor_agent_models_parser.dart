/// Parses `cursor-agent models` stdout into model ids.
List<String> parseCursorAgentModelsOutput(String stdout) {
  final models = <String>[];
  var inList = false;
  for (final rawLine in stdout.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('Tip:')) break;
    if (line == 'Available models') {
      inList = true;
      continue;
    }
    if (!inList) continue;
    final id = parseCursorAgentModelLineId(line);
    if (id != null && id.isNotEmpty) {
      models.add(id);
    }
  }
  return models;
}

/// Extracts the model id from a line like `gpt-5.2 - GPT-5.2`.
String? parseCursorAgentModelLineId(String line) {
  final dash = line.indexOf(' - ');
  if (dash <= 0) return null;
  return line.substring(0, dash).trim();
}

/// Returns the id marked `(current, default)` when present.
String? parseCursorAgentDefaultModelId(String stdout) {
  for (final rawLine in stdout.split('\n')) {
    final line = rawLine.trim();
    if (!line.contains('(current, default)')) continue;
    return parseCursorAgentModelLineId(line);
  }
  return null;
}
