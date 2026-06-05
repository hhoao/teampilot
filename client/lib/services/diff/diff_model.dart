/// Pure data model for the side-by-side diff viewer.
///
/// No Flutter dependency so the engine can run in an isolate (`compute()`).
library;

/// Classification of an aligned [DiffRow].
enum DiffRowKind {
  /// Both sides identical.
  equal,

  /// Present on the right only (left is a filler).
  insert,

  /// Present on the left only (right is a filler).
  delete,

  /// Both sides present but changed; carries inline char edits.
  modify,
}

/// A character range `[start, end)` (UTF-16 offsets) within a single line that
/// was added or removed, used for inline highlighting on a modify row.
class InlineEdit {
  const InlineEdit({
    required this.start,
    required this.end,
    required this.isAdd,
  });

  final int start;
  final int end;

  /// `true` => inserted text (right side), `false` => deleted text (left side).
  final bool isAdd;

  @override
  bool operator ==(Object other) =>
      other is InlineEdit &&
      other.start == start &&
      other.end == end &&
      other.isAdd == isAdd;

  @override
  int get hashCode => Object.hash(start, end, isAdd);

  @override
  String toString() =>
      'InlineEdit($start..$end, ${isAdd ? 'add' : 'del'})';
}

/// One aligned row across both panes. Filler sides have a null line number and
/// null text.
class DiffRow {
  const DiffRow({
    required this.kind,
    this.leftLineNo,
    this.rightLineNo,
    this.leftText,
    this.rightText,
    this.leftInline = const [],
    this.rightInline = const [],
  });

  final DiffRowKind kind;

  /// 1-based source line number on the left, or null for a filler row.
  final int? leftLineNo;

  /// 1-based source line number on the right, or null for a filler row.
  final int? rightLineNo;

  final String? leftText;
  final String? rightText;

  /// Deleted ranges within [leftText] (only on modify rows).
  final List<InlineEdit> leftInline;

  /// Inserted ranges within [rightText] (only on modify rows).
  final List<InlineEdit> rightInline;

  bool get hasLeft => leftLineNo != null;
  bool get hasRight => rightLineNo != null;

  @override
  bool operator ==(Object other) =>
      other is DiffRow &&
      other.kind == kind &&
      other.leftLineNo == leftLineNo &&
      other.rightLineNo == rightLineNo &&
      other.leftText == leftText &&
      other.rightText == rightText &&
      _listEq(other.leftInline, leftInline) &&
      _listEq(other.rightInline, rightInline);

  @override
  int get hashCode => Object.hash(
        kind,
        leftLineNo,
        rightLineNo,
        leftText,
        rightText,
        Object.hashAll(leftInline),
        Object.hashAll(rightInline),
      );

  @override
  String toString() =>
      'DiffRow(${kind.name}, L$leftLineNo R$rightLineNo)';
}

/// A maximal run of consecutive non-equal rows, used for the connecting ribbon
/// and next/previous-change navigation. [startRow] is inclusive, [endRow]
/// exclusive, both indexing into [DiffResult.rows].
class DiffBlock {
  const DiffBlock({
    required this.startRow,
    required this.endRow,
    required this.kind,
  });

  final int startRow;
  final int endRow;

  /// [DiffRowKind.insert], [DiffRowKind.delete], or [DiffRowKind.modify].
  final DiffRowKind kind;

  @override
  bool operator ==(Object other) =>
      other is DiffBlock &&
      other.startRow == startRow &&
      other.endRow == endRow &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(startRow, endRow, kind);

  @override
  String toString() => 'DiffBlock($startRow..$endRow, ${kind.name})';
}

/// Result of diffing two texts: the aligned rows plus derived change blocks and
/// summary counts.
class DiffResult {
  DiffResult({required this.rows, required this.blocks});

  final List<DiffRow> rows;
  final List<DiffBlock> blocks;

  int get addedLines =>
      rows.where((r) => r.kind == DiffRowKind.insert).length;
  int get removedLines =>
      rows.where((r) => r.kind == DiffRowKind.delete).length;
  int get modifiedLines =>
      rows.where((r) => r.kind == DiffRowKind.modify).length;

  bool get hasChanges => blocks.isNotEmpty;
}

bool _listEq(List<InlineEdit> a, List<InlineEdit> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
