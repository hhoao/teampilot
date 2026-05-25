import 'package:crypto/crypto.dart';

/// Remote plugin origin from Claude Code `marketplace.json` (`git-subdir`, `url`, `github`).
class PluginExternalSource {
  const PluginExternalSource({
    required this.cloneUrl,
    this.subPath = '',
    this.ref,
    this.sha,
  });

  final String cloneUrl;
  final String subPath;
  final String? ref;
  final String? sha;

  /// Stable cache folder name under `plugins/external-cache/`.
  String get cacheKey {
    final payload = '$cloneUrl|${ref ?? ''}|${sha ?? ''}';
    return sha256.convert(payload.codeUnits).toString().substring(0, 16);
  }

  /// Parses marketplace `source` when it is a JSON object (not a repo-relative path).
  static PluginExternalSource? fromMarketplaceObject(Map<String, Object?> map) {
    final kind = map['source'] as String? ?? '';
    switch (kind) {
      case 'git-subdir':
        final url = _normalizeCloneUrl(map['url'] as String? ?? '');
        final path = _cleanSubPath(map['path'] as String? ?? '');
        if (url.isEmpty) return null;
        return PluginExternalSource(
          cloneUrl: url,
          subPath: path,
          ref: _nonEmpty(map['ref'] as String?),
          sha: _nonEmpty(map['sha'] as String?),
        );
      case 'url':
        final url = _normalizeCloneUrl(map['url'] as String? ?? '');
        if (url.isEmpty) return null;
        return PluginExternalSource(
          cloneUrl: url,
          subPath: _cleanSubPath(map['path'] as String? ?? ''),
          ref: _nonEmpty(map['ref'] as String?),
          sha: _nonEmpty(map['sha'] as String?),
        );
      case 'github':
        final repo = (map['repo'] as String? ?? '').trim();
        if (repo.isEmpty) return null;
        final parts = repo.split('/');
        if (parts.length < 2) return null;
        final owner = parts[0];
        final name = parts[1].replaceAll(RegExp(r'\.git$'), '');
        return PluginExternalSource(
          cloneUrl: 'https://github.com/$owner/$name.git',
          subPath: _cleanSubPath(map['path'] as String? ?? ''),
          sha: _nonEmpty(map['sha'] as String?) ?? _nonEmpty(map['commit'] as String?),
        );
      default:
        return null;
    }
  }

  static String _normalizeCloneUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return '';
    if (!u.endsWith('.git') && u.contains('github.com/')) {
      u = '$u.git';
    }
    return u;
  }

  static String _cleanSubPath(String path) {
    var p = path.trim().replaceAll('\\', '/');
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    return p;
  }

  static String? _nonEmpty(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginExternalSource &&
          cloneUrl == other.cloneUrl &&
          subPath == other.subPath &&
          ref == other.ref &&
          sha == other.sha;

  @override
  int get hashCode => Object.hash(cloneUrl, subPath, ref, sha);
}
