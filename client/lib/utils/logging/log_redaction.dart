/// Redaction helpers for log output.
///
/// Process environment maps carry credentials (e.g. `OPENCODE_AUTH_CONTENT`),
/// but debug logs must stay debuggable, so instead of dropping values we mask
/// only secret-looking entries.
library;

/// Key-name markers: if the uppercased env key contains any of these, the
/// value is treated as secret.
const List<String> _sensitiveKeyMarkers = [
  'TOKEN',
  'KEY',
  'SECRET',
  'PASSWORD',
  'PASSWD',
  'AUTH',
  'CREDENTIAL',
  'PRIVATE',
];

/// Fallback value patterns for credentials that may hide under innocent key
/// names (e.g. a bearer token stored as `LLM_CONFIG`).
final List<RegExp> _secretValuePatterns = [
  RegExp(r'^sk-[A-Za-z0-9_\-]{8,}$'),
  RegExp(r'^gh[pousr]_[A-Za-z0-9]{20,}$'),
  RegExp(r'^glpat-[A-Za-z0-9_\-]{16,}$'),
  RegExp(r'^Bearer\s+\S+', caseSensitive: false),
  RegExp(r'^eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+$'),
  RegExp(r'^xox[baprs]-[A-Za-z0-9\-]{10,}$'),
  RegExp(r'^AKIA[0-9A-Z]{16}$'),
];

bool _looksSensitive(String key, String value) {
  final upper = key.toUpperCase();
  for (final marker in _sensitiveKeyMarkers) {
    if (upper.contains(marker)) return true;
  }
  for (final pattern in _secretValuePatterns) {
    if (pattern.hasMatch(value)) return true;
  }
  return false;
}

/// Formats [env] as `key=value, …` for debug logs, masking secret-looking
/// entries. The masked form keeps the entry length so a populated-but-redacted
/// variable stays distinguishable from a missing one.
String stringifyEnvironmentForLog(Map<String, String>? env) {
  if (env == null || env.isEmpty) return '';
  return env.entries
      .map((e) => _looksSensitive(e.key, e.value)
          ? '${e.key}=<redacted(len=${e.value.length})>'
          : '${e.key}=${e.value}')
      .join(', ');
}
