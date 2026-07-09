import 'package:flutter/services.dart';

import '../inline_token/inline_token_edit.dart';
import '../inline_token/inline_token_palette.dart';

export '../inline_token/inline_token_edit.dart';

typedef ComposeTokenRange = InlineTokenRange;

Iterable<ComposeTokenRange> composeTokenRanges(String text) =>
    inlineTokenRanges(text, defaultInlineTokenPattern);

ComposeTokenRange? composeTokenRangeForBackspace(String text, int offset) =>
    inlineTokenRangeForBackspace(text, offset, defaultInlineTokenPattern);

ComposeTokenRange? composeTokenRangeForDelete(String text, int offset) =>
    inlineTokenRangeForDelete(text, offset, defaultInlineTokenPattern);

TextRange expandRangeToComposeTokens({
  required String text,
  required int start,
  required int end,
}) {
  return expandRangeToInlineTokens(
    text: text,
    start: start,
    end: end,
    pattern: defaultInlineTokenPattern,
  );
}

TextEditingValue? applyComposeTokenBackspace(TextEditingValue value) =>
    applyInlineTokenBackspace(value, defaultInlineTokenPattern);

TextEditingValue? applyComposeTokenDelete(TextEditingValue value) =>
    applyInlineTokenDelete(value, defaultInlineTokenPattern);
