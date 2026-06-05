import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/diff/diff_engine.dart';
import 'package:teampilot/services/diff/diff_model.dart';
import 'package:teampilot/services/diff/diff_options.dart';

void main() {
  group('computeLineDiff', () {
    test('identical text yields all equal rows and no blocks', () {
      final result = computeLineDiff('a\nb\nc', 'a\nb\nc');

      expect(result.rows.map((r) => r.kind),
          everyElement(DiffRowKind.equal));
      expect(result.hasChanges, isFalse);
      expect(result.rows.length, 3);
      expect(result.rows[0].leftLineNo, 1);
      expect(result.rows[0].rightLineNo, 1);
    });

    test('pure insertion produces insert rows with left fillers', () {
      final result = computeLineDiff('a\nc', 'a\nb\nc');

      final insert = result.rows.firstWhere(
          (r) => r.kind == DiffRowKind.insert);
      expect(insert.rightText, 'b');
      expect(insert.hasLeft, isFalse);
      expect(insert.rightLineNo, 2);
      expect(result.addedLines, 1);
      expect(result.removedLines, 0);
    });

    test('pure deletion produces delete rows with right fillers', () {
      final result = computeLineDiff('a\nb\nc', 'a\nc');

      final delete = result.rows.firstWhere(
          (r) => r.kind == DiffRowKind.delete);
      expect(delete.leftText, 'b');
      expect(delete.hasRight, isFalse);
      expect(delete.leftLineNo, 2);
      expect(result.removedLines, 1);
    });

    test('changed line becomes a modify row with line numbers on both sides',
        () {
      final result = computeLineDiff('hello world', 'hello there');

      expect(result.rows.length, 1);
      final row = result.rows.single;
      expect(row.kind, DiffRowKind.modify);
      expect(row.leftLineNo, 1);
      expect(row.rightLineNo, 1);
      expect(row.leftText, 'hello world');
      expect(row.rightText, 'hello there');
    });

    test('modify row carries coalesced inline char edits', () {
      // "LABEL, REMARK" -> "LABEL, REMARK, LEVEL": only ", LEVEL" added.
      final result = computeLineDiff('LABEL, REMARK', 'LABEL, REMARK, LEVEL');
      final row = result.rows.single;

      expect(row.kind, DiffRowKind.modify);
      expect(row.leftInline, isEmpty);
      expect(row.rightInline.length, 1);
      final edit = row.rightInline.single;
      expect(edit.isAdd, isTrue);
      expect(row.rightText!.substring(edit.start, edit.end), ', LEVEL');
    });

    test('empty inputs produce no rows and no changes', () {
      final result = computeLineDiff('', '');
      expect(result.rows, isEmpty);
      expect(result.hasChanges, isFalse);
    });

    test('from-empty produces all inserts', () {
      final result = computeLineDiff('', 'x\ny');
      expect(result.rows.map((r) => r.kind),
          everyElement(DiffRowKind.insert));
      expect(result.addedLines, 2);
    });

    test('CRLF and trailing newline are normalized', () {
      final result = computeLineDiff('a\r\nb\r\n', 'a\nb\n');
      expect(result.hasChanges, isFalse);
      expect(result.rows.length, 2);
    });

    test('ignoreWhitespace treats reindented lines as equal', () {
      final strict = computeLineDiff('  foo()', 'foo()');
      expect(strict.hasChanges, isTrue);

      final lenient = computeLineDiff(
        '  foo()',
        'foo()',
        options: const DiffOptions(ignoreWhitespace: true),
      );
      expect(lenient.hasChanges, isFalse);
    });

    test('ignoreCase treats case-only changes as equal', () {
      final lenient = computeLineDiff(
        'Hello',
        'hello',
        options: const DiffOptions(ignoreCase: true),
      );
      expect(lenient.hasChanges, isFalse);
    });

    test('blocks group consecutive changes and classify them', () {
      // line1 equal, then 2 edited (similar) lines, then equal -> two modifies.
      final result = computeLineDiff(
        'a\nold line one\nold line two\nz',
        'a\nnew line one\nnew line two\nz',
      );
      expect(result.blocks.length, 1);
      final block = result.blocks.single;
      expect(block.kind, DiffRowKind.modify);
      // Block spans the two modify rows (indices 1..3).
      expect(block.endRow - block.startRow, 2);
      expect(result.modifiedLines, 2);
    });

    test('separate change regions yield separate blocks', () {
      final result = computeLineDiff(
        'a\nb\nc\nd\ne',
        'a\nB\nc\nd\nE',
      );
      expect(result.blocks.length, 2);
    });

    test('large input completes quickly', () {
      final left = List.generate(2000, (i) => 'line $i').join('\n');
      final right =
          List.generate(2000, (i) => i == 1000 ? 'line 1000 changed' : 'line $i')
              .join('\n');

      final sw = Stopwatch()..start();
      final result = computeLineDiff(left, right);
      sw.stop();

      // 'line 1000' -> 'line 1000 changed' is similar enough to pair as a modify.
      expect(result.modifiedLines, 1);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });
}
