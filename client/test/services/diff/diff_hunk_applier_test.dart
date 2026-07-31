import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/diff/diff_engine.dart';
import 'package:teampilot/services/diff/diff_hunk_applier.dart';
import 'package:teampilot/services/diff/diff_model.dart';

void main() {
  test('applyLeftToRight restores a deleted line (left → right)', () {
    final result = computeLineDiff('a\nb\nc', 'a\nc');
    final block = result.blocks.single;
    expect(block.kind, DiffRowKind.delete);

    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: block,
      rightFileText: 'a\nc',
    );
    expect(next, 'a\nb\nc');
  });

  test('applyLeftToRight drops an inserted line', () {
    final result = computeLineDiff('a\nc', 'a\nb\nc');
    final block = result.blocks.single;
    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: block,
      rightFileText: 'a\nb\nc',
    );
    expect(next, 'a\nc');
  });

  test('applyLeftToRight replaces a modify line', () {
    final result = computeLineDiff('hello world', 'hello there');
    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: result.blocks.single,
      rightFileText: 'hello there',
    );
    expect(next, 'hello world');
  });

  test('invalid block throws StateError', () {
    final result = computeLineDiff('a', 'b');
    expect(
      () => DiffHunkApplier.applyLeftToRight(
        result: result,
        block: const DiffBlock(
          startRow: 9,
          endRow: 10,
          kind: DiffRowKind.modify,
        ),
        rightFileText: 'b',
      ),
      throwsStateError,
    );
  });

  test('applyLeftToRight restores a line deleted at file head', () {
    final result = computeLineDiff('a\nb', 'b');
    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: result.blocks.single,
      rightFileText: 'b',
    );
    expect(next, 'a\nb');
  });

  test('applyLeftToRight restores a line deleted at file tail', () {
    final result = computeLineDiff('a\nb\nc', 'a\nb');
    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: result.blocks.single,
      rightFileText: 'a\nb',
    );
    expect(next, 'a\nb\nc');
  });

  test('applyLeftToRight on empty right file inserts left content', () {
    final result = computeLineDiff('x\ny', '');
    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: result.blocks.single,
      rightFileText: '',
    );
    expect(next, 'x\ny');
  });

  test('consecutive applyLeftToRight calls compose', () {
    final left = 'a\nb\nc\nd';
    var right = 'a\nc\nd';
    var result = computeLineDiff(left, right);

    right = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: result.blocks.first,
      rightFileText: right,
    );
    expect(right, 'a\nb\nc\nd');

    result = computeLineDiff(left, 'a\nb\nc');
    right = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: result.blocks.single,
      rightFileText: 'a\nb\nc',
    );
    expect(right, left);
  });

  test('applyLeftToRight preserves trailing newline on right file', () {
    final result = computeLineDiff('a\nb', 'a');
    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: result.blocks.single,
      rightFileText: 'a\n',
    );
    expect(next, 'a\nb\n');
  });

  test('applyLeftToRight without trailing newline stays bare', () {
    final result = computeLineDiff('a\nb', 'a');
    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: result.blocks.single,
      rightFileText: 'a',
    );
    expect(next, 'a\nb');
    expect(next.endsWith('\n'), isFalse);
  });

  group('canonicalSideText', () {
    test('collects non-filler left lines in order', () {
      final result = computeLineDiff('a\nb\nc', 'a\nc');
      expect(
        canonicalSideText(result.rows, right: false),
        'a\nb\nc',
      );
    });

    test('collects non-filler right lines in order', () {
      final result = computeLineDiff('a\nb\nc', 'a\nc');
      expect(
        canonicalSideText(result.rows, right: true),
        'a\nc',
      );
    });

    test('preferTrailingNewline appends final newline', () {
      final result = computeLineDiff('a\nb', 'a');
      expect(
        canonicalSideText(result.rows, right: true, preferTrailingNewline: true),
        'a\n',
      );
    });
  });
}
