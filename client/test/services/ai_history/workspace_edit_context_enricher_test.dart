import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/workspace_edit_context_enricher.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  AiEditHunk inputHunk() => const AiEditHunk(
    path: 'lib/tp_sidebar_provider.dart',
    addedCount: 2,
    removedCount: 1,
    lines: [
      AiEditLine(
        kind: AiEditLineKind.remove,
        text: 'final double mobileBreakpoint;',
      ),
      AiEditLine(
        kind: AiEditLineKind.add,
        text: 'final double mobileBreakpoint;',
      ),
      AiEditLine(
        kind: AiEditLineKind.add,
        text: 'final bool enableKeyboardShortcut,',
      ),
    ],
  );

  test('adds context lines and absolute numbers when remove anchor found', () async {
    fs.files['/workspace/lib/tp_sidebar_provider.dart'] =
        'before ctx\n'
        'final double mobileBreakpoint;\n'
        'final bool enableKeyboardShortcut,\n'
        'after ctx\n';

    final enricher = WorkspaceEditContextEnricher(
      fs: fs,
      sessionWorkingDirectory: null,
      workspaceFolderPaths: const ['/workspace'],
    );

    final enriched = await enricher.enrich(inputHunk());

    expect(enriched.startLine, 1);
    expect(
      enriched.lines.map((l) => (l.kind, l.text, l.lineNumber)).toList(),
      [
        (AiEditLineKind.context, 'before ctx', 1),
        (AiEditLineKind.remove, 'final double mobileBreakpoint;', 2),
        (AiEditLineKind.add, 'final double mobileBreakpoint;', 2),
        (AiEditLineKind.add, 'final bool enableKeyboardShortcut,', 3),
        (AiEditLineKind.context, 'final bool enableKeyboardShortcut,', 3),
        (AiEditLineKind.context, 'after ctx', 4),
      ],
    );
    expect(enriched.addedCount, 2);
    expect(enriched.removedCount, 1);
  });

  test('resolves relative path against session working directory first', () async {
    fs.files['/session/lib/foo.dart'] = 'ctx\nold line\nafter\n';
    fs.files['/workspace/lib/foo.dart'] = 'other\n';

    final enricher = WorkspaceEditContextEnricher(
      fs: fs,
      sessionWorkingDirectory: '/session',
      workspaceFolderPaths: const ['/workspace'],
    );

    final enriched = await enricher.enrich(
      const AiEditHunk(
        path: 'lib/foo.dart',
        addedCount: 1,
        removedCount: 1,
        lines: [
          AiEditLine(kind: AiEditLineKind.remove, text: 'old line'),
          AiEditLine(kind: AiEditLineKind.add, text: 'new line'),
        ],
      ),
    );

    expect(enriched.lines.first.text, 'ctx');
    expect(enriched.lines.first.lineNumber, 1);
  });

  test('file missing returns input hunk unchanged', () async {
    final input = inputHunk();
    final enricher = WorkspaceEditContextEnricher(
      fs: fs,
      sessionWorkingDirectory: null,
      workspaceFolderPaths: const ['/workspace'],
    );

    final enriched = await enricher.enrich(input);

    expect(enriched.path, input.path);
    expect(enriched.lines, input.lines);
    expect(enriched.startLine, input.startLine);
    expect(enriched.addedCount, input.addedCount);
    expect(enriched.removedCount, input.removedCount);
  });

  test('anchor lost returns input hunk unchanged', () async {
    fs.files['/workspace/lib/tp_sidebar_provider.dart'] = 'totally different content\n';

    final input = inputHunk();
    final enricher = WorkspaceEditContextEnricher(
      fs: fs,
      sessionWorkingDirectory: null,
      workspaceFolderPaths: const ['/workspace'],
    );

    final enriched = await enricher.enrich(input);

    expect(enriched.lines, input.lines);
    expect(enriched.startLine, input.startLine);
  });
}
