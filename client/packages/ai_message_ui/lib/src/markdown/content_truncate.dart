import 'content_ir.dart';

/// Budget approximating Claude Code webview `oYe` default maxHeight ≈ 250px.
class ContentCollapseBudget {
  const ContentCollapseBudget({
    this.maxBlocks = 8,
    this.maxTableRows = 6,
    this.maxChars = 1200,
  });

  final int maxBlocks;
  final int maxTableRows;
  final int maxChars;

  /// Tuned to Claude Code 2.1.212 `oYe({ maxHeight: 250 })` open cost.
  static const ContentCollapseBudget claudeAligned = ContentCollapseBudget();
}

class TruncatedMessageContent {
  const TruncatedMessageContent({
    required this.document,
    required this.wasTruncated,
  });

  final MessageContentDocument document;
  final bool wasTruncated;
}

/// Prefix of [full] within [budget]. Omits widgets Flutter would still layout
/// under a CSS-style maxHeight clip.
TruncatedMessageContent truncateMessageContent(
  MessageContentDocument full, {
  ContentCollapseBudget budget = ContentCollapseBudget.claudeAligned,
}) {
  final blocks = full.blocks;
  if (blocks.isEmpty) {
    return TruncatedMessageContent(document: full, wasTruncated: false);
  }

  final out = <ContentBlock>[];
  var chars = 0;
  var wasTruncated = false;

  for (var i = 0; i < blocks.length; i++) {
    if (out.length >= budget.maxBlocks) {
      wasTruncated = true;
      break;
    }

    final original = blocks[i];
    var block = original;
    if (original is TableBlock &&
        original.rows.length > budget.maxTableRows) {
      block = TableBlock(
        headers: original.headers,
        rows: original.rows.sublist(0, budget.maxTableRows),
      );
      wasTruncated = true;
    }

    final blockChars = _estimateBlockChars(block);
    if (chars + blockChars > budget.maxChars) {
      if (out.isEmpty) {
        final clipped = _clipBlockToChars(block, budget.maxChars);
        out.add(clipped.block);
        wasTruncated = wasTruncated || clipped.wasTruncated;
      } else {
        wasTruncated = true;
      }
      break;
    }

    out.add(block);
    chars += blockChars;
  }

  if (out.length < blocks.length) {
    wasTruncated = true;
  }

  if (!wasTruncated) {
    return TruncatedMessageContent(document: full, wasTruncated: false);
  }

  return TruncatedMessageContent(
    document: MessageContentDocument(blocks: List.unmodifiable(out)),
    wasTruncated: true,
  );
}

({ContentBlock block, bool wasTruncated}) _clipBlockToChars(
  ContentBlock block,
  int maxChars,
) {
  return switch (block) {
    ParagraphBlock(:final runs) => () {
        final clipped = _clipRuns(runs, maxChars);
        return (
          block: ParagraphBlock(runs: clipped.runs) as ContentBlock,
          wasTruncated: clipped.wasTruncated,
        );
      }(),
    HeadingBlock(:final level, :final runs) => () {
        final clipped = _clipRuns(runs, maxChars);
        return (
          block: HeadingBlock(level: level, runs: clipped.runs) as ContentBlock,
          wasTruncated: clipped.wasTruncated,
        );
      }(),
    CodeBlock(:final language, :final text) => () {
        if (text.length <= maxChars) {
          return (block: block as ContentBlock, wasTruncated: false);
        }
        return (
          block: CodeBlock(
            language: language,
            text: '${text.substring(0, maxChars)}…',
          ) as ContentBlock,
          wasTruncated: true,
        );
      }(),
    _ => (block: block, wasTruncated: true),
  };
}

({List<InlineRun> runs, bool wasTruncated}) _clipRuns(
  List<InlineRun> runs,
  int maxChars,
) {
  final out = <InlineRun>[];
  var remaining = maxChars;
  var wasTruncated = false;

  for (final run in runs) {
    if (remaining <= 0) {
      wasTruncated = true;
      break;
    }
    if (run is TextRun) {
      if (run.text.length <= remaining) {
        out.add(run);
        remaining -= run.text.length;
      } else {
        out.add(TextRun('${run.text.substring(0, remaining)}…'));
        wasTruncated = true;
        remaining = 0;
        break;
      }
      continue;
    }
    final len = _estimateRunsChars([run]);
    if (len <= remaining) {
      out.add(run);
      remaining -= len;
    } else {
      wasTruncated = true;
      break;
    }
  }

  if (out.length < runs.length) {
    wasTruncated = true;
  }

  return (runs: out, wasTruncated: wasTruncated);
}

int _estimateBlockChars(ContentBlock block) {
  return switch (block) {
    ParagraphBlock(:final runs) => _estimateRunsChars(runs),
    HeadingBlock(:final runs) => _estimateRunsChars(runs),
    CodeBlock(:final text) => text.length,
    HorizontalRuleBlock() => 0,
    UnsupportedBlock(:final rawMarkdown) => rawMarkdown.length,
    BlockquoteBlock(:final blocks) =>
      blocks.fold<int>(0, (sum, b) => sum + _estimateBlockChars(b)),
    ListBlock(:final items) => items.fold<int>(0, (sum, item) {
        return sum +
            _estimateRunsChars(item.runs) +
            item.children.fold<int>(0, (s, b) => s + _estimateBlockChars(b));
      }),
    TableBlock(:final headers, :final rows) => () {
        var n = 0;
        for (final h in headers) {
          n += _estimateRunsChars(h.runs);
        }
        for (final row in rows) {
          for (final cell in row) {
            n += _estimateRunsChars(cell.runs);
          }
        }
        return n;
      }(),
  };
}

int _estimateRunsChars(List<InlineRun> runs) {
  var n = 0;
  for (final run in runs) {
    n += switch (run) {
      TextRun(:final text) => text.length,
      CodeRun(:final text) => text.length,
      StrongRun(:final children) => _estimateRunsChars(children),
      EmphasisRun(:final children) => _estimateRunsChars(children),
      StrikeRun(:final children) => _estimateRunsChars(children),
      LinkRun(:final children) => _estimateRunsChars(children),
    };
  }
  return n;
}
