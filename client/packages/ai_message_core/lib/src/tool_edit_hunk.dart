enum AiEditLineKind { context, add, remove }

class AiEditLine {
  const AiEditLine({
    required this.kind,
    required this.text,
    this.lineNumber,
  });

  final AiEditLineKind kind;
  final String text;
  final int? lineNumber;
}

class AiEditHunk {
  const AiEditHunk({
    required this.path,
    required this.lines,
    required this.addedCount,
    required this.removedCount,
    this.startLine,
  });

  final String path;
  final List<AiEditLine> lines;
  final int addedCount;
  final int removedCount;
  final int? startLine;
}

class AiEditToolTarget {
  const AiEditToolTarget({required this.hunk});

  final AiEditHunk hunk;
}
