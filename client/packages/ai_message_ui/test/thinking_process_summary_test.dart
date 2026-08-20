import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _MapFileResolver implements AiToolFileTargetResolver {
  const _MapFileResolver(this.paths);

  final Map<String, String> paths;

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) {
    final path = paths[part.toolCallId];
    if (path == null) return null;
    return AiToolFileTarget(path: path);
  }
}

class _MapEditResolver implements AiEditToolTargetResolver {
  const _MapEditResolver(this.hunks);

  final Map<String, AiEditHunk> hunks;

  @override
  AiEditToolTarget? resolve(AiToolCallPart part) {
    final hunk = hunks[part.toolCallId];
    if (hunk == null) return null;
    return AiEditToolTarget(hunk: hunk);
  }
}

AiToolCallPart _tool({
  required String id,
  required String name,
  required AiToolCallCategory category,
}) {
  return AiToolCallPart(toolCallId: id, toolName: name, category: category);
}

AiEditHunk _hunk(String path, {int added = 0, int removed = 0}) {
  return AiEditHunk(
    path: path,
    lines: const [],
    addedCount: added,
    removedCount: removed,
  );
}

void main() {
  test('reasoning-only has no activity', () {
    expect(
      summarizeThinkingProcess(const [AiReasoningPart(text: 'plan')]),
      const AiThinkingProcessSummary(),
    );
  });

  test('unannotated tools do not count as activity', () {
    final summary = summarizeThinkingProcess([
      _tool(id: '1', name: 'Read', category: AiToolCallCategory.other),
      _tool(id: '2', name: 'Grep', category: AiToolCallCategory.other),
      _tool(id: '3', name: 'Bash', category: AiToolCallCategory.other),
    ]);
    expect(summary.hasActivity, isFalse);
  });

  test('counts unique files, grep as search, commands, and hunk diffs', () {
    final summary = summarizeThinkingProcess(
      [
        const AiReasoningPart(text: 'plan'),
        _tool(id: 'e1', name: 'Edit', category: AiToolCallCategory.edit),
        _tool(id: 'e2', name: 'Edit', category: AiToolCallCategory.edit),
        _tool(id: 'w1', name: 'Write', category: AiToolCallCategory.write),
        _tool(id: 'r1', name: 'Read', category: AiToolCallCategory.read),
        _tool(id: 'r2', name: 'Read', category: AiToolCallCategory.read),
        _tool(id: 'g1', name: 'Grep', category: AiToolCallCategory.read),
        _tool(id: 's1', name: 'WebSearch', category: AiToolCallCategory.search),
        _tool(id: 'c1', name: 'Bash', category: AiToolCallCategory.command),
        _tool(id: 'c2', name: 'Bash', category: AiToolCallCategory.command),
      ],
      fileResolver: const _MapFileResolver({
        'r1': 'a.dart',
        'r2': 'b.dart',
        'g1': 'a.dart',
      }),
      editResolver: _MapEditResolver({
        'e1': _hunk('a.dart', added: 10, removed: 2),
        'e2': _hunk('a.dart', added: 5, removed: 1),
        'w1': _hunk('c.dart', added: 4),
      }),
    );

    expect(
      summary,
      const AiThinkingProcessSummary(
        editedFiles: 2,
        exploredFiles: 2,
        searches: 2,
        commands: 2,
        added: 19,
        removed: 3,
      ),
    );
    expect(
      defaultThinkingProcessSummaryLabel(summary),
      'Edited 2 files, explored 2 files, 2 searches, ran 2 commands',
    );
  });

  test('unresolved categorized reads still count as explored files', () {
    final summary = summarizeThinkingProcess([
      _tool(id: 'r1', name: 'Read', category: AiToolCallCategory.read),
      _tool(id: 'r2', name: 'Glob', category: AiToolCallCategory.read),
    ]);
    expect(summary.exploredFiles, 2);
    expect(defaultThinkingProcessSummaryLabel(summary), 'Explored 2 files');
  });

  test('singular default labels', () {
    expect(
      defaultThinkingProcessSummaryLabel(
        const AiThinkingProcessSummary(editedFiles: 1, searches: 1),
      ),
      'Edited 1 file, 1 search',
    );
    expect(
      defaultThinkingProcessSummaryLabel(
        const AiThinkingProcessSummary(exploredFiles: 1, commands: 1),
      ),
      'Explored 1 file, ran 1 command',
    );
  });

  test('other categories are omitted from the summary', () {
    final summary = summarizeThinkingProcess([
      _tool(id: 't', name: 'Task', category: AiToolCallCategory.subagent),
      _tool(id: 'm', name: 'mcp__x', category: AiToolCallCategory.mcp),
    ]);
    expect(summary.hasActivity, isFalse);
    expect(defaultThinkingProcessSummaryLabel(summary), isEmpty);
  });
}
