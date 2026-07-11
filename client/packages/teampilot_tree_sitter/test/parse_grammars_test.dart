import 'dart:convert';
import 'dart:typed_data';

import 'package:teampilot_tree_sitter/teampilot_tree_sitter.dart';
import 'package:test/test.dart';

/// One smoke case per bundled grammar: parse a tiny sample and assert the
/// requested capture shows up, which proves the grammar + its external scanner
/// linked into the native asset and produce a usable tree.
class _GrammarCase {
  const _GrammarCase(this.id, this.language, this.source, this.query, this.capture);

  final String id;
  final TsLanguage Function() language;
  final String source;
  final String query;
  final String capture;
}

final _cases = <_GrammarCase>[
  _GrammarCase('json', TsLanguage.json, '{"a": 1}', '(string) @string', 'string'),
  _GrammarCase(
    'dart',
    TsLanguage.dart,
    'void main() {}',
    '(identifier) @id',
    'id',
  ),
  _GrammarCase('yaml', TsLanguage.yaml, 'a: 1\nb: two\n', '(block_mapping_pair) @pair', 'pair'),
  _GrammarCase(
    'markdown',
    TsLanguage.markdown,
    '# Heading\n\ntext\n',
    '(atx_heading) @heading',
    'heading',
  ),
  _GrammarCase(
    'python',
    TsLanguage.python,
    'def f():\n    return 1\n',
    '(function_definition) @fn',
    'fn',
  ),
  _GrammarCase(
    'rust',
    TsLanguage.rust,
    'fn main() {}',
    '(function_item) @fn',
    'fn',
  ),
  _GrammarCase(
    'typescript',
    TsLanguage.typescript,
    'const x: number = 1;',
    '(lexical_declaration) @decl',
    'decl',
  ),
  _GrammarCase(
    'bash',
    TsLanguage.bash,
    'echo hello\n',
    '(command) @cmd',
    'cmd',
  ),
  _GrammarCase(
    'xml',
    TsLanguage.xml,
    '<root><child>x</child></root>',
    '(element) @el',
    'el',
  ),
  _GrammarCase(
    'toml',
    TsLanguage.toml,
    'key = "value"\n',
    '(pair) @pair',
    'pair',
  ),
  _GrammarCase(
    'css',
    TsLanguage.css,
    'a { color: red; }',
    '(rule_set) @rule',
    'rule',
  ),
];

void main() {
  for (final c in _cases) {
    test('parses_${c.id}_smoke', () {
      final lang = c.language();
      final parser = TsParser()..setLanguage(lang);
      final bytes = utf8.encode(c.source);
      final tree = parser.parseUtf8(Uint8List.fromList(bytes));
      final query = TsQuery(lang, c.query);
      final caps = query.captures(tree, startByte: 0, endByte: bytes.length);
      expect(
        caps.any((cap) => cap.name == c.capture),
        isTrue,
        reason: 'expected a @${c.capture} capture for ${c.id}',
      );

      query.dispose();
      tree.dispose();
      parser.dispose();
    });
  }
}
