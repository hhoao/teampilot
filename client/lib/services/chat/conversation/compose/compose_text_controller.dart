import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'compose_token_document.dart';

/// Compose text controller that keeps explicit token ranges in sync with the
/// text.
///
/// Nothing is inferred from the text: a token exists only because
/// [insertToken] / [insertReferences] created it. Pasted or typed text that
/// happens to look like `@path` / `/skill` stays plain text.
class ComposeTextController extends TextEditingController {
  ComposeTextController({super.text}) {
    _remember(text, _document);
  }

  static const _historyLimit = 200;

  ComposeTokenDocument _document = ComposeTokenDocument.empty;
  var _nextTokenId = 0;

  /// Recent `(text -> document)` pairs. Flutter's undo/redo restores text
  /// through [value]; matching the text restores the token ranges with it.
  final _history = <String, ComposeTokenDocument>{};
  final _historyOrder = Queue<String>();

  ComposeTokenDocument get document => _document;

  List<TextRange> get tokenRanges => _document.ranges;

  @override
  set value(TextEditingValue newValue) {
    final oldText = super.value.text;
    if (newValue.text != oldText) {
      _document =
          _history[newValue.text] ??
          _document.applyEdit(oldText, newValue.text);
      _remember(newValue.text, _document);
    }
    super.value = newValue;
  }

  /// Replaces [start]..[end] with [tokenText] + [suffix] and records a token
  /// covering exactly [tokenText]. [suffix] stays plain text, so typing after
  /// it can never extend the token.
  void insertToken({
    required int start,
    required int end,
    required String tokenText,
    String suffix = ' ',
    required ComposeTokenKind kind,
    required String payload,
  }) {
    final old = super.value;
    final replacement = '$tokenText$suffix';
    final next = old.copyWith(
      text: old.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
      composing: TextRange.empty,
    );
    _document = _document
        .applyEdit(old.text, next.text)
        .add(
          ComposeToken(
            id: '${_nextTokenId++}',
            kind: kind,
            start: start,
            end: start + tokenText.length,
            payload: payload,
          ),
        );
    _remember(next.text, _document);
    super.value = next;
  }

  /// Inserts `@` references as tokens, joined by one space and followed by a
  /// space. Adds a leading separator when the caret is not already at one.
  void insertReferences(Iterable<String> references) {
    final refs = references
        .map((reference) => reference.trim())
        .where((reference) => reference.isNotEmpty)
        .toList(growable: false);
    if (refs.isEmpty) return;

    final old = super.value;
    final selection = old.selection.isValid
        ? old.selection
        : TextSelection.collapsed(offset: old.text.length);
    final wantsPrefix =
        selection.start > 0 && old.text[selection.start - 1] != ' ';
    final buffer = StringBuffer();
    var offset = selection.start + (wantsPrefix ? 1 : 0);
    final tokens = <ComposeToken>[];
    if (wantsPrefix) buffer.write(' ');
    for (var index = 0; index < refs.length; index++) {
      if (index > 0) {
        buffer.write(' ');
        offset++;
      }
      tokens.add(
        ComposeToken(
          id: '${_nextTokenId++}',
          kind: ComposeTokenKind.fileReference,
          start: offset,
          end: offset + refs[index].length,
          payload: refs[index],
        ),
      );
      buffer.write(refs[index]);
      offset += refs[index].length;
    }
    buffer.write(' ');

    final replacement = buffer.toString();
    final next = old.copyWith(
      text: old.text.replaceRange(selection.start, selection.end, replacement),
      selection: TextSelection.collapsed(
        offset: selection.start + replacement.length,
      ),
      composing: TextRange.empty,
    );
    var nextDocument = _document.applyEdit(old.text, next.text);
    for (final token in tokens) {
      nextDocument = nextDocument.add(token);
    }
    _document = nextDocument;
    _remember(next.text, _document);
    super.value = next;
  }

  void _remember(String text, ComposeTokenDocument document) {
    if (_history.containsKey(text)) {
      _historyOrder.remove(text);
    }
    _history[text] = document;
    _historyOrder.addLast(text);
    while (_historyOrder.length > _historyLimit) {
      _history.remove(_historyOrder.removeFirst());
    }
  }
}
