/// Returns the canonical target-safe directory name for a neutral skill
/// contribution.
///
/// Names are deliberately restricted to a portable subset shared by POSIX
/// and Windows filesystems. A namespace is separated with `--`, never `/` or
/// `:`, so the returned value is safe to use as a single directory basename.
String targetSafeSkillLinkName(String invocationName, {String? namespace}) {
  final safeName = _safeSegment(invocationName);
  final trimmedNamespace = namespace?.trim();
  if (trimmedNamespace == null || trimmedNamespace.isEmpty) return safeName;
  return '${_safeSegment(trimmedNamespace)}--$safeName';
}

String _safeSegment(String value) {
  var safe = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  safe = safe.replaceAll(RegExp(r'[ .]+$'), '');
  if (safe.isEmpty || safe == '.' || safe == '..') return 'skill';
  return safe;
}
