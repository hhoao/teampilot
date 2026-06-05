/// Maps aligned [DiffRow]s onto what the two re-editor panes need: per-side
/// text + gutter line numbers (theme-independent) and per-side
/// [CodeLineDecoration]s (theme-dependent).
///
/// Both panes always have exactly `rows.length` visual lines (fillers are blank
/// lines), so the two editors align line-for-line and vertical scroll maps 1:1.
library;

import 'dart:ui';

import 'package:re_editor/re_editor.dart';

import 'diff_model.dart';

/// Color palette for diff backgrounds. Bands are faint full-line fills; inline
/// colors are stronger and drawn over the band on modify rows.
class DiffColors {
  const DiffColors({
    required this.addBand,
    required this.addInline,
    required this.removeBand,
    required this.removeInline,
    required this.fillerBand,
    required this.ribbonAdd,
    required this.ribbonRemove,
    required this.ribbonModify,
  });

  final Color addBand;
  final Color addInline;
  final Color removeBand;
  final Color removeInline;

  /// Muted band painted on the empty side opposite an insert/delete.
  final Color fillerBand;

  /// Center-gutter connecting-ribbon fills, one per change kind.
  final Color ribbonAdd;
  final Color ribbonRemove;
  final Color ribbonModify;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiffColors &&
          other.addBand == addBand &&
          other.addInline == addInline &&
          other.removeBand == removeBand &&
          other.removeInline == removeInline &&
          other.fillerBand == fillerBand &&
          other.ribbonAdd == ribbonAdd &&
          other.ribbonRemove == ribbonRemove &&
          other.ribbonModify == ribbonModify;

  @override
  int get hashCode => Object.hash(addBand, addInline, removeBand, removeInline,
      fillerBand, ribbonAdd, ribbonRemove, ribbonModify);
}

/// Theme-independent text + gutter numbers for both panes.
class DiffPaneTexts {
  const DiffPaneTexts({
    required this.leftText,
    required this.rightText,
    required this.leftNumbers,
    required this.rightNumbers,
  });

  final String leftText;
  final String rightText;

  /// One entry per visual line; null marks a filler line (no number).
  final List<int?> leftNumbers;
  final List<int?> rightNumbers;
}

/// Theme-dependent decorations for both panes.
class DiffPaneDecorations {
  const DiffPaneDecorations({required this.left, required this.right});

  final List<CodeLineDecoration> left;
  final List<CodeLineDecoration> right;
}

/// Single-column unified rendering: text, gutter numbers, decorations, and the
/// change blocks in unified-line coordinates (for navigation + overview ruler).
class UnifiedPane {
  const UnifiedPane({
    required this.text,
    required this.numbers,
    required this.decorations,
    required this.blocks,
  });

  final String text;
  final List<int?> numbers;
  final List<CodeLineDecoration> decorations;

  /// Change blocks with [DiffBlock.startRow]/[DiffBlock.endRow] as unified line
  /// indices.
  final List<DiffBlock> blocks;

  /// Total unified line count.
  int get lineCount => numbers.length;
}

DiffPaneTexts buildDiffPaneTexts(List<DiffRow> rows) {
  final left = StringBuffer();
  final right = StringBuffer();
  final leftNumbers = <int?>[];
  final rightNumbers = <int?>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (i > 0) {
      left.write('\n');
      right.write('\n');
    }
    left.write(row.leftText ?? '');
    right.write(row.rightText ?? '');
    leftNumbers.add(row.leftLineNo);
    rightNumbers.add(row.rightLineNo);
  }
  return DiffPaneTexts(
    leftText: left.toString(),
    rightText: right.toString(),
    leftNumbers: leftNumbers,
    rightNumbers: rightNumbers,
  );
}

UnifiedPane buildUnifiedPane(List<DiffRow> rows, DiffColors colors) {
  final buffer = StringBuffer();
  final numbers = <int?>[];
  final decorations = <CodeLineDecoration>[];
  final blocks = <DiffBlock>[];
  var line = 0;
  var runStart = -1;
  var runAdd = false;
  var runRemove = false;
  var runModify = false;

  void closeRun() {
    if (runStart < 0) return;
    final DiffRowKind kind;
    if (runModify || (runAdd && runRemove)) {
      kind = DiffRowKind.modify;
    } else if (runAdd) {
      kind = DiffRowKind.insert;
    } else {
      kind = DiffRowKind.delete;
    }
    blocks.add(DiffBlock(startRow: runStart, endRow: line, kind: kind));
    runStart = -1;
    runAdd = runRemove = runModify = false;
  }

  void emit(String text, int? number) {
    if (line > 0) buffer.write('\n');
    buffer.write(text);
    numbers.add(number);
  }

  CodeLineDecoration band(int at, Color color) => CodeLineDecoration(
        selection: CodeLineSelection.collapsed(index: at, offset: 0),
        color: color,
        fillLine: true,
      );

  CodeLineDecoration inline(int at, InlineEdit edit, Color color) =>
      CodeLineDecoration(
        selection: CodeLineSelection(
          baseIndex: at,
          baseOffset: edit.start,
          extentIndex: at,
          extentOffset: edit.end,
        ),
        color: color,
      );

  for (final row in rows) {
    if (row.kind == DiffRowKind.equal) {
      closeRun();
      emit(row.leftText ?? '', row.rightLineNo ?? row.leftLineNo);
      line++;
      continue;
    }
    if (runStart < 0) runStart = line;
    switch (row.kind) {
      case DiffRowKind.delete:
        emit(row.leftText ?? '', row.leftLineNo);
        decorations.add(band(line, colors.removeBand));
        line++;
        runRemove = true;
      case DiffRowKind.insert:
        emit(row.rightText ?? '', row.rightLineNo);
        decorations.add(band(line, colors.addBand));
        line++;
        runAdd = true;
      case DiffRowKind.modify:
        emit(row.leftText ?? '', row.leftLineNo);
        decorations.add(band(line, colors.removeBand));
        for (final edit in row.leftInline) {
          decorations.add(inline(line, edit, colors.removeInline));
        }
        line++;
        emit(row.rightText ?? '', row.rightLineNo);
        decorations.add(band(line, colors.addBand));
        for (final edit in row.rightInline) {
          decorations.add(inline(line, edit, colors.addInline));
        }
        line++;
        runModify = true;
      case DiffRowKind.equal:
        break;
    }
  }
  closeRun();

  return UnifiedPane(
    text: buffer.toString(),
    numbers: numbers,
    decorations: decorations,
    blocks: blocks,
  );
}

DiffPaneDecorations buildDiffPaneDecorations(
  List<DiffRow> rows,
  DiffColors colors,
) {
  final left = <CodeLineDecoration>[];
  final right = <CodeLineDecoration>[];

  CodeLineDecoration band(int line, Color color) => CodeLineDecoration(
        selection: CodeLineSelection.collapsed(index: line, offset: 0),
        color: color,
        fillLine: true,
      );

  CodeLineDecoration inline(int line, InlineEdit edit, Color color) =>
      CodeLineDecoration(
        selection: CodeLineSelection(
          baseIndex: line,
          baseOffset: edit.start,
          extentIndex: line,
          extentOffset: edit.end,
        ),
        color: color,
      );

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    switch (row.kind) {
      case DiffRowKind.equal:
        break;
      case DiffRowKind.delete:
        left.add(band(i, colors.removeBand));
        right.add(band(i, colors.fillerBand));
      case DiffRowKind.insert:
        left.add(band(i, colors.fillerBand));
        right.add(band(i, colors.addBand));
      case DiffRowKind.modify:
        // Band first, inline ranges on top (later in list = painted above).
        left.add(band(i, colors.removeBand));
        right.add(band(i, colors.addBand));
        for (final edit in row.leftInline) {
          left.add(inline(i, edit, colors.removeInline));
        }
        for (final edit in row.rightInline) {
          right.add(inline(i, edit, colors.addInline));
        }
    }
  }
  return DiffPaneDecorations(left: left, right: right);
}
