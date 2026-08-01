import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('table cell inline code with angle brackets stays a TableBlock', () {
    // Regression: `_looksLikeHtml` used to fire on Text inside <code>,
    // collapsing the whole GFM table into RawLiteralBlock.
    const src = '''
## More documentation

| Doc | Audience | Topic |
|-----|----------|--------|
| [Development guide](docs/DEVELOPMENT.md) | Contributors / maintainers | Setup, run, test, package, CI |
| [AGENTS.md](AGENTS.md) | Contributors / AI | Repo layout, architecture, conventions |
| [Workspace storage layout](docs/workspace-storage-layout.md) | Contributors / AI | On-disk paths under `<teampilotRoot>` |
''';
    final doc = compileMarkdown(src);
    expect(doc.blocks.whereType<RawLiteralBlock>(), isEmpty);
    final table = doc.blocks.whereType<TableBlock>().single;
    expect(table.headers, hasLength(3));
    expect(table.rows, hasLength(3));
    final lastCell = table.rows.last.last.runs;
    expect(lastCell.whereType<CodeRun>(), isNotEmpty);
    expect(
      (lastCell.whereType<CodeRun>().single).text,
      '<teampilotRoot>',
    );
  });
}
