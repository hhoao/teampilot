import 'package:flutter/services.dart';

class InlineTokenRange {
  const InlineTokenRange({required this.start, required this.end});

  final int start;
  final int end;
}

Iterable<InlineTokenRange> inlineTokenRanges(String text, RegExp pattern) sync* {
  for (final match in pattern.allMatches(text)) {
    yield InlineTokenRange(start: match.start, end: match.end);
  }
}

InlineTokenRange? inlineTokenRangeForBackspace(
  String text,
  int offset,
  RegExp pattern,
) {
  for (final token in inlineTokenRanges(text, pattern)) {
    if (offset > token.start && offset <= token.end) {
      return token;
    }
  }
  return null;
}

InlineTokenRange? inlineTokenRangeForDelete(
  String text,
  int offset,
  RegExp pattern,
) {
  for (final token in inlineTokenRanges(text, pattern)) {
    if (offset >= token.start && offset < token.end) {
      return token;
    }
  }
  return null;
}

TextRange expandRangeToInlineTokens({
  required String text,
  required int start,
  required int end,
  required RegExp pattern,
}) {
  var expandedStart = start;
  var expandedEnd = end;
  for (final token in inlineTokenRanges(text, pattern)) {
    if (token.end <= expandedStart || token.start >= expandedEnd) {
      continue;
    }
    if (token.start < expandedStart) expandedStart = token.start;
    if (token.end > expandedEnd) expandedEnd = token.end;
  }
  return TextRange(start: expandedStart, end: expandedEnd);
}

TextEditingValue? applyInlineTokenBackspace(
  TextEditingValue value,
  RegExp pattern,
) {
  final text = value.text;
  final selection = value.selection;
  if (!selection.isValid) return null;

  if (!selection.isCollapsed) {
    final expanded = expandRangeToInlineTokens(
      text: text,
      start: selection.start,
      end: selection.end,
      pattern: pattern,
    );
    if (expanded.start == selection.start && expanded.end == selection.end) {
      return null;
    }
    return value.copyWith(
      text: text.replaceRange(expanded.start, expanded.end, ''),
      selection: TextSelection.collapsed(offset: expanded.start),
      composing: TextRange.empty,
    );
  }

  final token = inlineTokenRangeForBackspace(
    text,
    selection.extentOffset,
    pattern,
  );
  if (token == null) return null;

  return value.copyWith(
    text: text.replaceRange(token.start, token.end, ''),
    selection: TextSelection.collapsed(offset: token.start),
    composing: TextRange.empty,
  );
}

TextEditingValue? applyInlineTokenDelete(
  TextEditingValue value,
  RegExp pattern,
) {
  final text = value.text;
  final selection = value.selection;
  if (!selection.isValid) return null;

  if (!selection.isCollapsed) {
    final expanded = expandRangeToInlineTokens(
      text: text,
      start: selection.start,
      end: selection.end,
      pattern: pattern,
    );
    if (expanded.start == selection.start && expanded.end == selection.end) {
      return null;
    }
    return value.copyWith(
      text: text.replaceRange(expanded.start, expanded.end, ''),
      selection: TextSelection.collapsed(offset: expanded.start),
      composing: TextRange.empty,
    );
  }

  final token = inlineTokenRangeForDelete(
    text,
    selection.extentOffset,
    pattern,
  );
  if (token == null) return null;

  return value.copyWith(
    text: text.replaceRange(token.start, token.end, ''),
    selection: TextSelection.collapsed(offset: token.start),
    composing: TextRange.empty,
  );
}
