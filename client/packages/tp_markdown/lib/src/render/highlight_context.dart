import 'package:flutter/material.dart';

/// One step on the route from a top-level block down to a nested text
/// container. A container address = top-level block index + ordered steps.
sealed class MarkdownPathStep {
  const MarkdownPathStep();
}

/// Into [ListBlock.items] at [item] (its own runs, or the prefix for children).
final class ListItemStep extends MarkdownPathStep {
  const ListItemStep(this.item);

  final int item;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ListItemStep && other.item == item;

  @override
  int get hashCode => Object.hash(ListItemStep, item);
}

/// Into nested child blocks (list-item children / blockquote children).
final class ChildStep extends MarkdownPathStep {
  const ChildStep(this.index);

  final int index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChildStep && other.index == index;

  @override
  int get hashCode => Object.hash(ChildStep, index);
}

/// Table header cell at column [col].
final class TableHeaderStep extends MarkdownPathStep {
  const TableHeaderStep(this.col);

  final int col;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TableHeaderStep && other.col == col;

  @override
  int get hashCode => Object.hash(TableHeaderStep, col);
}

/// Table body cell at [row] x [col].
final class TableCellStep extends MarkdownPathStep {
  const TableCellStep(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TableCellStep && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(TableCellStep, row, col);
}

/// Highlights for one text container: every match range plus the currently
/// navigated one (rendered stronger).
class MarkdownContainerHighlights {
  const MarkdownContainerHighlights({required this.ranges, this.active});

  /// All match ranges within the container's plain text.
  final List<TextRange> ranges;

  /// The active match (must be contained in one of [ranges]); `null` = none.
  final TextRange? active;
}

/// Resolves per-container highlight ranges during rendering. Views look up by
/// address and pass the result down into span building.
abstract interface class MarkdownHighlightContext {
  MarkdownContainerHighlights? forContainer(
    int blockIndex,
    List<MarkdownPathStep> path,
  );
}
