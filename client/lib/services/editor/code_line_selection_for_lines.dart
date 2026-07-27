import 'package:re_editor/re_editor.dart';

/// Builds a [CodeLineSelection] for 1-based inclusive line numbers.
///
/// [startLine] and [endLine] are clamped to the document. When [endLine] is
/// omitted, only [startLine] is selected through end-of-line.
CodeLineSelection codeLineSelectionForLines({
  required int lineCount,
  required List<int> lineLengths,
  required int startLine, // 1-based
  int? endLine,
}) {
  if (lineCount <= 0) {
    return const CodeLineSelection.collapsed(index: 0, offset: 0);
  }
  final start = (startLine - 1).clamp(0, lineCount - 1);
  final end = ((endLine ?? startLine) - 1).clamp(0, lineCount - 1);
  final lo = start <= end ? start : end;
  final hi = start <= end ? end : start;
  return CodeLineSelection(
    baseIndex: lo,
    baseOffset: 0,
    extentIndex: hi,
    extentOffset: lineLengths[hi],
  );
}
