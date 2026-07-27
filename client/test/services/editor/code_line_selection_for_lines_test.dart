import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/code_line_selection_for_lines.dart';

void main() {
  test('single line selection', () {
    final sel = codeLineSelectionForLines(
      lineCount: 10,
      lineLengths: List.filled(10, 5),
      startLine: 3,
    );
    expect(sel.baseIndex, 2);
    expect(sel.baseOffset, 0);
    expect(sel.extentIndex, 2);
    expect(sel.extentOffset, 5);
  });

  test('range clamps to document', () {
    final sel = codeLineSelectionForLines(
      lineCount: 5,
      lineLengths: List.filled(5, 1),
      startLine: 1,
      endLine: 99,
    );
    expect(sel.extentIndex, 4);
  });
}
