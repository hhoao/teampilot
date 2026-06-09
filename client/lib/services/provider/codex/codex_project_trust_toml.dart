import '../../../utils/project_path_utils.dart';

/// Injects Codex project trust tables into `config.toml`.
///
/// Codex prompts for directory trust when `[projects."<path>"]` is missing or
/// not marked trusted. See upstream `config.toml` examples:
/// `trust_level = "trusted"`.
abstract final class CodexProjectTrustToml {
  CodexProjectTrustToml._();

  static const trustLevel = 'trusted';

  /// Appends `[projects."…"]` blocks for [directories] not already trusted.
  static String applyTrustedDirectories(
    String toml,
    Iterable<String> directories,
  ) {
    final trimmed = toml.trim();
    final blocks = <String>[];
    final seen = <String>{};

    for (final directory in directories) {
      for (final path in projectMetadataKeys(directory)) {
        if (!seen.add(path)) continue;
        if (_isDirectoryTrusted(trimmed, path)) continue;
        blocks.add(_trustBlock(path));
      }
    }

    if (blocks.isEmpty) return trimmed;
    if (trimmed.isEmpty) return blocks.join('\n\n');
    return '$trimmed\n\n${blocks.join('\n\n')}';
  }

  static bool _isDirectoryTrusted(String toml, String path) {
    final header = _tableHeader(path);
    if (!toml.contains(header)) return false;
    final start = toml.indexOf(header);
    final end = (start + 200) > toml.length ? toml.length : start + 200;
    final slice = toml.substring(start, end);
    return slice.contains('trust_level = "trusted"') ||
        slice.contains("trust_level = 'trusted'");
  }

  static String _trustBlock(String path) {
    return '${_tableHeader(path)}\ntrust_level = "$trustLevel"';
  }

  static String _tableHeader(String path) {
    final escaped = path.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '[projects."$escaped"]';
  }
}
