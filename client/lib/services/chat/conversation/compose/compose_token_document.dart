import 'dart:math' as math;

import 'package:flutter/services.dart';

/// What an explicitly inserted compose token represents.
enum ComposeTokenKind { fileReference, skill, command }

/// One atomic compose token. [payload] is the exact text the CLI must receive
/// (e.g. `@src/main.dart`, `/plan`).
class ComposeToken {
  const ComposeToken({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    required this.payload,
  });

  final String id;
  final ComposeTokenKind kind;
  final int start;
  final int end;
  final String payload;

  TextRange get range => TextRange(start: start, end: end);

  ComposeToken shift(int delta) => ComposeToken(
    id: id,
    kind: kind,
    start: start + delta,
    end: end + delta,
    payload: payload,
  );
}

/// Token ranges for one compose text.
///
/// Text remains the only storage — the wire format is still plain text — but
/// ranges are the authority for rendering and atomic edits. A token exists
/// only because the insertion command created it; no regex re-derives tokens
/// from text.
class ComposeTokenDocument {
  const ComposeTokenDocument._(this.tokens);

  static const empty = ComposeTokenDocument._(<ComposeToken>[]);

  final List<ComposeToken> tokens;

  List<TextRange> get ranges => [for (final token in tokens) token.range];

  ComposeTokenDocument add(ComposeToken token) {
    final next = [...tokens, token]..sort((a, b) => a.start.compareTo(b.start));
    return ComposeTokenDocument._(next);
  }

  /// Token a Backspace at [offset] should delete as one unit.
  ComposeToken? tokenForBackspace(int offset) {
    for (final token in tokens) {
      if (offset > token.start && offset <= token.end) return token;
    }
    return null;
  }

  /// Token a Delete at [offset] should delete as one unit.
  ComposeToken? tokenForDelete(int offset) {
    for (final token in tokens) {
      if (offset >= token.start && offset < token.end) return token;
    }
    return null;
  }

  /// Applies one text change.
  ///
  /// An insertion strictly inside a token, or any deletion that touches a
  /// token, dissolves it: the user edited the token's text, so it is no longer
  /// the object that was inserted. Insertions at either boundary keep the
  /// token (the chip stays atomic; the new text is plain text beside it).
  ComposeTokenDocument applyEdit(String oldText, String newText) {
    if (oldText == newText) return this;
    final splice = _singleSplice(oldText, newText);
    final replaceStart = splice.start;
    final replaceEnd = splice.start + splice.removed;
    final out = <ComposeToken>[];
    for (final token in tokens) {
      final intersects = splice.removed == 0
          ? token.start < replaceStart && replaceStart < token.end
          : replaceStart < token.end && token.start < replaceEnd;
      if (intersects) continue;
      out.add(replaceEnd <= token.start ? token.shift(splice.delta) : token);
    }
    return ComposeTokenDocument._(out);
  }
}

class _Splice {
  const _Splice(this.start, this.removed, this.inserted);

  final int start;
  final int removed;
  final String inserted;

  int get delta => inserted.length - removed;
}

/// The single contiguous replacement that turns [oldText] into [newText].
_Splice _singleSplice(String oldText, String newText) {
  final maxPrefix = math.min(oldText.length, newText.length);
  var prefix = 0;
  while (prefix < maxPrefix &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < maxPrefix - prefix &&
      oldText.codeUnitAt(oldText.length - 1 - suffix) ==
          newText.codeUnitAt(newText.length - 1 - suffix)) {
    suffix++;
  }
  return _Splice(
    prefix,
    oldText.length - prefix - suffix,
    newText.substring(prefix, newText.length - suffix),
  );
}
