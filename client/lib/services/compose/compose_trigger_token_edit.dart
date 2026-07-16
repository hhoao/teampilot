import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../inline_token/inline_token_palette.dart';

typedef ComposeTokenRange = TpTokenRange;

Iterable<ComposeTokenRange> composeTokenRanges(String text) =>
    tpTokenRanges(text, defaultInlineTokenPattern);

ComposeTokenRange? composeTokenRangeForBackspace(String text, int offset) =>
    tpTokenRangeForBackspace(text, offset, defaultInlineTokenPattern);

ComposeTokenRange? composeTokenRangeForDelete(String text, int offset) =>
    tpTokenRangeForDelete(text, offset, defaultInlineTokenPattern);

TextRange expandRangeToComposeTokens({
  required String text,
  required int start,
  required int end,
}) {
  return expandRangeToTpTokens(
    text: text,
    start: start,
    end: end,
    pattern: defaultInlineTokenPattern,
  );
}

TextEditingValue? applyComposeTokenBackspace(TextEditingValue value) =>
    applyTpTokenBackspace(value, defaultInlineTokenPattern);

TextEditingValue? applyComposeTokenDelete(TextEditingValue value) =>
    applyTpTokenDelete(value, defaultInlineTokenPattern);
