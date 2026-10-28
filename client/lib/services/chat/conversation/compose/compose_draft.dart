import 'compose_token_document.dart';

/// One persisted compose draft: plain text plus the explicit token ranges that
/// belonged to it.
///
/// The wire format sent to the CLI stays plain text; tokens are only restored
/// when [text] still matches the saved token slices. Older drafts (plain
/// strings in [ComposeDraftStore]) decode with no tokens.
class ComposeDraft {
  const ComposeDraft({required this.text, this.tokens = const []});

  final String text;
  final List<ComposeToken> tokens;

  bool get isEmpty => text.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toJson() => {
    'text': text,
    'tokens': [
      for (final token in tokens)
        {
          'kind': token.kind.name,
          'start': token.start,
          'end': token.end,
          'payload': token.payload,
        },
    ],
  };

  /// Accepts both the legacy plain-string value and the map written by
  /// [toJson]. Tokens that no longer match [text] are dropped.
  static ComposeDraft? fromJson(Object? raw) {
    if (raw is String) return ComposeDraft(text: raw);
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String) return null;

    final tokens = <ComposeToken>[];
    final rawTokens = raw['tokens'];
    if (rawTokens is List) {
      var lastEnd = -1;
      for (var index = 0; index < rawTokens.length; index++) {
        final entry = rawTokens[index];
        if (entry is! Map) continue;
        final kindName = entry['kind'];
        final start = entry['start'];
        final end = entry['end'];
        final payload = entry['payload'];
        if (kindName is! String ||
            start is! int ||
            end is! int ||
            payload is! String) {
          continue;
        }
        final kind = _kindFromName(kindName);
        if (kind == null || start < 0 || end > text.length || end <= start) {
          continue;
        }
        if (start < lastEnd) continue;
        if (text.substring(start, end) != payload) continue;
        tokens.add(
          ComposeToken(
            id: 'draft-$index',
            kind: kind,
            start: start,
            end: end,
            payload: payload,
          ),
        );
        lastEnd = end;
      }
    }
    return ComposeDraft(text: text, tokens: tokens);
  }
}

ComposeTokenKind? _kindFromName(String name) {
  for (final kind in ComposeTokenKind.values) {
    if (kind.name == name) return kind;
  }
  return null;
}
