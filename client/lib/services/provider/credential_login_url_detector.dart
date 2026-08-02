/// Extracts https login URLs from CLI stdout/stderr text.
class CredentialLoginUrlDetector {
  const CredentialLoginUrlDetector();

  static final RegExp _httpsUrl = RegExp(
    r'https://[^\s<>"\u0027]+',
    caseSensitive: false,
  );

  static const _preferredHostHints = [
    'cursor',
    'claude',
    'anthropic',
    'openai',
    'oauth',
    'login',
    'auth',
  ];

  /// All distinct https URIs, preferred hosts first.
  List<Uri> extractAll(String text) {
    final found = <Uri>[];
    final seen = <String>{};
    for (final match in _httpsUrl.allMatches(text)) {
      var raw = match.group(0)!;
      raw = raw.replaceFirst(RegExp(r'[)\],.;:]+$'), '');
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.scheme.toLowerCase() != 'https') continue;
      final key = uri.toString();
      if (!seen.add(key)) continue;
      found.add(uri);
    }
    found.sort((a, b) {
      final ap = _isPreferred(a) ? 0 : 1;
      final bp = _isPreferred(b) ? 0 : 1;
      return ap.compareTo(bp);
    });
    return found;
  }

  Uri? extractFirst(String text) {
    final all = extractAll(text);
    return all.isEmpty ? null : all.first;
  }

  bool _isPreferred(Uri uri) {
    final host = uri.host.toLowerCase();
    return _preferredHostHints.any(host.contains);
  }
}
