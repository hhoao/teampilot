/// Extracts https login URLs from CLI stdout/stderr text.
class CredentialLoginUrlDetector {
  const CredentialLoginUrlDetector();

  static final RegExp _httpsUrl = RegExp(
    r'https://[^\s<>"\u0027\x1b]+',
    caseSensitive: false,
  );

  static final RegExp _ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

  /// Codex-style device codes (`ABCD-EFGHI`).
  ///
  /// Piped/TUI output often glues the code to the next sentence
  /// (`WO3M-X8OIFContinue`), so accept a following `Continue` as a terminator.
  static final RegExp _deviceCode = RegExp(
    r'\b([A-Z0-9]{4,5}-[A-Z0-9]{4,8})(?=Continue|\b)',
  );

  static final RegExp _openaiDeviceUrl = RegExp(
    r'https://auth\.openai\.com/codex/device',
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

  /// Strip CSI / SGR sequences so colored CLI banners still parse.
  static String stripAnsi(String text) => text.replaceAll(_ansi, '');

  /// All distinct https URIs, preferred hosts first.
  List<Uri> extractAll(String text) {
    final cleaned = stripAnsi(text);
    final found = <Uri>[];
    final seen = <String>{};
    for (final match in _httpsUrl.allMatches(cleaned)) {
      var raw = match.group(0)!;
      raw = raw.replaceFirst(RegExp(r'[)\],.;:]+$'), '');
      final openaiDevice = _openaiDeviceUrl.firstMatch(raw);
      if (openaiDevice != null) {
        raw = openaiDevice.group(0)!;
      }
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

  /// Device codes from Codex `--device-auth` banners (deduped).
  List<String> extractDeviceCodes(String text) {
    final cleaned = stripAnsi(text);
    final found = <String>[];
    final seen = <String>{};
    for (final match in _deviceCode.allMatches(cleaned)) {
      final code = match.group(1)!;
      if (seen.add(code)) found.add(code);
    }
    return found;
  }

  bool _isPreferred(Uri uri) {
    final host = uri.host.toLowerCase();
    return _preferredHostHints.any(host.contains);
  }
}
