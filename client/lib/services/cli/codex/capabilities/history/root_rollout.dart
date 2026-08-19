import 'dart:convert';

import '../../../../io/filesystem.dart';

/// Filename UUID of a Codex `rollout-*.jsonl` (last uuid before `.jsonl`).
final codexRolloutId = RegExp(
  r'rollout-.*-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
  r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$',
);

class CodexRootRollout {
  const CodexRootRollout({required this.path, required this.uuid});

  final String path;
  final String uuid;
}

/// Newest **root** rollout under `$CODEX_HOME/sessions`.
///
/// Spawn_agent children are sibling `rollout-*.jsonl` files whose first
/// `session_meta` carries `parent_thread_id` / `thread_source=subagent` /
/// `source.subagent`. Lexicographic-max over those files is the running
/// child — the seat and resume id must stay on the parent, same as
/// OpenCode's `parent_id IS NULL` filter.
///
/// A persisted uuid that points at a child is ignored so an already-flipped
/// binding can recover on the next locate / detect.
Future<CodexRootRollout?> pickCodexRootRollout({
  required Filesystem fs,
  required String codexHome,
  String? persistedNativeId,
}) async {
  final home = codexHome.trim();
  if (home.isEmpty) return null;
  final path = fs.pathContext;
  final sessionsDir = path.join(home, 'sessions');
  final wanted = persistedNativeId?.trim() ?? '';

  final roots = <_Hit>[];
  _Hit? wantedHit;

  try {
    final entries = await fs.listDirRecursive(sessionsDir);
    for (final e in entries) {
      if (e.isDirectory) continue;
      if (_isUnderSubagents(e.name)) continue;
      final name = path.basename(e.name);
      final match = codexRolloutId.firstMatch(name);
      if (match == null) continue;
      final uuid = match.group(1) ?? '';
      if (uuid.isEmpty) continue;
      final fullPath = path.join(sessionsDir, e.name);
      final child = await _isChildRollout(fs, fullPath);
      final hit = _Hit(rel: e.name, path: fullPath, uuid: uuid, child: child);
      if (wanted.isNotEmpty && uuid == wanted) wantedHit = hit;
      if (!child) roots.add(hit);
    }
  } on Object {
    return null;
  }

  if (wantedHit != null && !wantedHit.child) return wantedHit.asRoot();
  if (roots.isEmpty) return null;
  roots.sort((a, b) => a.rel.compareTo(b.rel));
  return roots.last.asRoot();
}

class _Hit {
  const _Hit({
    required this.rel,
    required this.path,
    required this.uuid,
    required this.child,
  });

  final String rel;
  final String path;
  final String uuid;
  final bool child;

  CodexRootRollout asRoot() => CodexRootRollout(path: path, uuid: uuid);
}

bool _isUnderSubagents(String relativePath) {
  return relativePath.split(RegExp(r'[/\\]')).contains('subagents');
}

/// First-line `session_meta` is ~20KB once `base_instructions` is inlined;
/// `parent_thread_id` / `source.subagent` sit in the first few hundred bytes.
const _peekBytes = 8192;

Future<bool> _isChildRollout(Filesystem fs, String path) async {
  final bytes = await fs.readBytesRange(path, 0, _peekBytes);
  if (bytes == null || bytes.isEmpty) return false;
  final text = utf8.decode(bytes, allowMalformed: true);
  final line = text.split('\n').first.trim();
  final obj = _tryDecodeObject(line);
  if (obj != null) {
    if ('${obj['type'] ?? ''}' != 'session_meta') return false;
    final payloadRaw = obj['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : null;
    return isCodexSubagentSessionMeta(payload);
  }
  return _looksLikeSubagentPrefix(text);
}

/// True when [payload] is a spawn_agent / thread-spawn child, not a user root.
bool isCodexSubagentSessionMeta(Map<String, dynamic>? payload) {
  if (payload == null) return false;
  final parent = '${payload['parent_thread_id'] ?? ''}'.trim();
  if (parent.isNotEmpty) return true;
  final threadSource = '${payload['thread_source'] ?? ''}'.trim().toLowerCase();
  if (threadSource == 'subagent') return true;
  final source = payload['source'];
  return source is Map && source.containsKey('subagent');
}

bool _looksLikeSubagentPrefix(String text) {
  return RegExp(r'"parent_thread_id"\s*:\s*"[^"]+"').hasMatch(text) ||
      RegExp(r'"thread_source"\s*:\s*"subagent"').hasMatch(text) ||
      RegExp(r'"source"\s*:\s*\{\s*"subagent"').hasMatch(text);
}

Map<String, dynamic>? _tryDecodeObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}
