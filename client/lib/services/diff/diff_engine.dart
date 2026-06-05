/// Pure diff engine: Myers O(ND) line diff + char-level inline diff, producing
/// aligned [DiffRow]s for the side-by-side viewer.
///
/// No Flutter dependency so it can run in an isolate (`compute()`).
library;

import 'diff_model.dart';
import 'diff_options.dart';
import 'line_pairing.dart';

/// Computes an aligned line diff between [left] and [right].
///
/// Replace blocks (adjacent delete-run + insert-run) are paired in index order
/// for now; similarity-based pairing is layered on in `line_pairing.dart`
/// (task 2). Paired lines additionally get char-level inline edits.
DiffResult computeLineDiff(
  String left,
  String right, {
  DiffOptions options = DiffOptions.none,
}) {
  final leftLines = _splitLines(left);
  final rightLines = _splitLines(right);

  final edits = _myers<String>(
    leftLines,
    rightLines,
    (a, b) => options.normalize(a) == options.normalize(b),
  );

  final rows = <DiffRow>[];
  var leftNo = 1;
  var rightNo = 1;
  var i = 0;
  while (i < edits.length) {
    final edit = edits[i];
    if (edit.type == _EditType.equal) {
      rows.add(DiffRow(
        kind: DiffRowKind.equal,
        leftLineNo: leftNo,
        rightLineNo: rightNo,
        leftText: leftLines[edit.aIndex],
        rightText: rightLines[edit.bIndex],
      ));
      leftNo++;
      rightNo++;
      i++;
      continue;
    }

    // Gather a maximal change block of consecutive non-equal edits.
    final dels = <String>[];
    final ins = <String>[];
    while (i < edits.length && edits[i].type != _EditType.equal) {
      final e = edits[i];
      if (e.type == _EditType.delete) {
        dels.add(leftLines[e.aIndex]);
      } else {
        ins.add(rightLines[e.bIndex]);
      }
      i++;
    }
    rows.addAll(buildChangeRows(
      dels,
      ins,
      leftStartNo: leftNo,
      rightStartNo: rightNo,
      options: options,
    ));
    leftNo += dels.length;
    rightNo += ins.length;
  }

  return DiffResult(rows: rows, blocks: buildBlocks(rows));
}

/// Aligns a single change block ([dels] removed lines + [ins] added lines) into
/// modify/delete/insert rows, with inline char edits on modify rows.
///
/// Exposed so the unified-diff parser can reuse the same pairing + inline logic
/// on the +/- runs git already classified.
List<DiffRow> buildChangeRows(
  List<String> dels,
  List<String> ins, {
  required int leftStartNo,
  required int rightStartNo,
  DiffOptions options = DiffOptions.none,
}) {
  final rows = <DiffRow>[];
  final ops = pairChangeBlock(dels, ins, options: options);
  for (final op in ops) {
    switch (op.kind) {
      case PairOpKind.modify:
        final left = dels[op.leftIndex];
        final right = ins[op.rightIndex];
        final inline = _charInline(left, right);
        rows.add(DiffRow(
          kind: DiffRowKind.modify,
          leftLineNo: leftStartNo + op.leftIndex,
          rightLineNo: rightStartNo + op.rightIndex,
          leftText: left,
          rightText: right,
          leftInline: inline.left,
          rightInline: inline.right,
        ));
      case PairOpKind.delete:
        rows.add(DiffRow(
          kind: DiffRowKind.delete,
          leftLineNo: leftStartNo + op.leftIndex,
          leftText: dels[op.leftIndex],
        ));
      case PairOpKind.insert:
        rows.add(DiffRow(
          kind: DiffRowKind.insert,
          rightLineNo: rightStartNo + op.rightIndex,
          rightText: ins[op.rightIndex],
        ));
    }
  }
  return rows;
}

/// Groups consecutive non-equal rows into [DiffBlock]s for the ribbon and
/// next/previous-change navigation.
List<DiffBlock> buildBlocks(List<DiffRow> rows) {
  final blocks = <DiffBlock>[];
  var i = 0;
  while (i < rows.length) {
    if (rows[i].kind == DiffRowKind.equal) {
      i++;
      continue;
    }
    final start = i;
    var sawModify = false;
    var sawInsert = false;
    var sawDelete = false;
    while (i < rows.length && rows[i].kind != DiffRowKind.equal) {
      switch (rows[i].kind) {
        case DiffRowKind.modify:
          sawModify = true;
        case DiffRowKind.insert:
          sawInsert = true;
        case DiffRowKind.delete:
          sawDelete = true;
        case DiffRowKind.equal:
          break;
      }
      i++;
    }
    final DiffRowKind kind;
    if (sawModify || (sawInsert && sawDelete)) {
      kind = DiffRowKind.modify;
    } else if (sawInsert) {
      kind = DiffRowKind.insert;
    } else {
      kind = DiffRowKind.delete;
    }
    blocks.add(DiffBlock(startRow: start, endRow: i, kind: kind));
  }
  return blocks;
}

/// Char-level diff of two lines -> deleted ranges on the left, inserted ranges
/// on the right (UTF-16 offsets), coalescing adjacent edits.
({List<InlineEdit> left, List<InlineEdit> right}) _charInline(
  String left,
  String right,
) {
  final a = left.codeUnits;
  final b = right.codeUnits;
  final edits = _myers<int>(a, b, (x, y) => x == y);

  final leftEdits = <InlineEdit>[];
  final rightEdits = <InlineEdit>[];
  var leftCol = 0;
  var rightCol = 0;
  for (final e in edits) {
    switch (e.type) {
      case _EditType.equal:
        leftCol++;
        rightCol++;
      case _EditType.delete:
        _extend(leftEdits, leftCol, leftCol + 1, isAdd: false);
        leftCol++;
      case _EditType.insert:
        _extend(rightEdits, rightCol, rightCol + 1, isAdd: true);
        rightCol++;
    }
  }
  return (left: leftEdits, right: rightEdits);
}

void _extend(
  List<InlineEdit> edits,
  int start,
  int end, {
  required bool isAdd,
}) {
  if (edits.isNotEmpty && edits.last.end == start) {
    final prev = edits.removeLast();
    edits.add(InlineEdit(start: prev.start, end: end, isAdd: isAdd));
  } else {
    edits.add(InlineEdit(start: start, end: end, isAdd: isAdd));
  }
}

List<String> _splitLines(String text) {
  if (text.isEmpty) return const [];
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  // Drop a single trailing empty element from a final newline so "a\nb\n"
  // diffs as two lines, matching typical line semantics.
  if (lines.length > 1 && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

// --- Myers O(ND) diff (Coglan formulation) ---------------------------------

enum _EditType { equal, delete, insert }

class _Edit {
  const _Edit(this.type, this.aIndex, this.bIndex);
  final _EditType type;
  final int aIndex; // index into a; -1 for insert
  final int bIndex; // index into b; -1 for delete
}

List<_Edit> _myers<T>(
  List<T> a,
  List<T> b,
  bool Function(T, T) eq,
) {
  final n = a.length;
  final m = b.length;
  if (n == 0 && m == 0) return const [];
  if (n == 0) {
    return [for (var j = 0; j < m; j++) _Edit(_EditType.insert, -1, j)];
  }
  if (m == 0) {
    return [for (var k = 0; k < n; k++) _Edit(_EditType.delete, k, -1)];
  }

  final max = n + m;
  final offset = max;
  final v = List<int>.filled(2 * max + 1, 0);
  final trace = <List<int>>[];
  var dFinal = -1;

  outer:
  for (var d = 0; d <= max; d++) {
    trace.add(List<int>.from(v));
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) {
        x = v[offset + k + 1]; // move down (insert from b)
      } else {
        x = v[offset + k - 1] + 1; // move right (delete from a)
      }
      var y = x - k;
      while (x < n && y < m && eq(a[x], b[y])) {
        x++;
        y++;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) {
        dFinal = d;
        break outer;
      }
    }
  }

  final path = <_Edit>[];
  var x = n;
  var y = m;
  for (var d = dFinal; d >= 0; d--) {
    final vPrev = trace[d];
    final k = x - y;
    int prevK;
    if (k == -d || (k != d && vPrev[offset + k - 1] < vPrev[offset + k + 1])) {
      prevK = k + 1;
    } else {
      prevK = k - 1;
    }
    final prevX = vPrev[offset + prevK];
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      path.add(_Edit(_EditType.equal, x - 1, y - 1));
      x--;
      y--;
    }
    if (d > 0) {
      if (x == prevX) {
        path.add(_Edit(_EditType.insert, -1, y - 1));
      } else {
        path.add(_Edit(_EditType.delete, x - 1, -1));
      }
    }
    x = prevX;
    y = prevY;
  }

  return path.reversed.toList();
}
