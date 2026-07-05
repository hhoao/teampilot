import 'package:flutter/material.dart';

/// Inserts [insertion] at the current selection in [controller].
TextEditingValue insertTextAtSelection(
  TextEditingController controller,
  String insertion, {
  String separatorBefore = '',
  String separatorAfter = '',
}) {
  final value = controller.value;
  final text = value.text;
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: text.length);
  final start = selection.start;
  final end = selection.end;

  final prefix = start > 0 && separatorBefore.isNotEmpty
      ? (text[start - 1] == ' ' ? '' : separatorBefore)
      : '';
  final suffix = separatorAfter;

  final chunk = '$prefix$insertion$suffix';
  final newText = text.replaceRange(start, end, chunk);
  return value.copyWith(
    text: newText,
    selection: TextSelection.collapsed(offset: start + chunk.length),
    composing: TextRange.empty,
  );
}
