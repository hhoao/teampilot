import 'package:toml/toml.dart';

import '../../io/filesystem.dart';

/// Reads a Grok `config.toml` into a mutable map. A malformed file is treated
/// as empty so TeamPilot can still provision the keys it owns.
Future<Map<String, Object?>> readGrokTomlMap(Filesystem fs, String path) async {
  final raw = await fs.readString(path);
  if (raw == null || raw.trim().isEmpty) return <String, Object?>{};
  try {
    return Map<String, Object?>.from(TomlDocument.parse(raw).toMap());
  } on Object {
    return <String, Object?>{};
  }
}

Future<void> writeGrokTomlMap(
  Filesystem fs,
  String path,
  Map<String, Object?> map,
) async {
  await fs.ensureDir(fs.pathContext.dirname(path));
  await fs.atomicWrite(path, TomlDocument.fromMap(map).toString());
}

/// Merges [values] into the `[section]` table, preserving unrelated keys and
/// tables.
Future<void> mergeGrokTomlSection({
  required Filesystem fs,
  required String configPath,
  required String section,
  required Map<String, Object?> values,
  bool replaceSection = false,
}) async {
  final map = await readGrokTomlMap(fs, configPath);
  final parts = section.split('.').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return;
  var cursor = map;
  for (final part in parts.take(parts.length - 1)) {
    final existing = cursor[part];
    final next = existing is Map
        ? Map<String, Object?>.from(
            existing.map((key, value) => MapEntry(key.toString(), value)),
          )
        : <String, Object?>{};
    cursor[part] = next;
    cursor = next;
  }
  final leaf = parts.last;
  final current = replaceSection
      ? <String, Object?>{}
      : Map<String, Object?>.from(
          (cursor[leaf] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value),
              ) ??
              const {},
        );
  current.addAll(values);
  cursor[leaf] = current;
  await writeGrokTomlMap(fs, configPath, map);
}

/// Disables Grok's foreign-harness compatibility scanners for an isolated
/// session. Without this, `GROK_HOME` isolates Grok's own files but Grok still
/// imports the user's `~/.claude.json`, `~/.cursor/`, and project
/// `.claude`/`.cursor` MCP servers, skills, rules, and hooks.
Future<void> writeGrokIsolationDefaults(
  Filesystem fs,
  String configPath,
) async {
  for (final section in const ['compat.claude', 'compat.cursor']) {
    await mergeGrokTomlSection(
      fs: fs,
      configPath: configPath,
      section: section,
      values: const {
        'skills': false,
        'rules': false,
        'agents': false,
        'mcps': false,
        'hooks': false,
        'sessions': false,
      },
    );
  }
  await mergeGrokTomlSection(
    fs: fs,
    configPath: configPath,
    section: 'compat.codex',
    values: const {'sessions': false},
  );
}
