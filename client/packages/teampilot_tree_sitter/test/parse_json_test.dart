import 'dart:convert';
import 'dart:typed_data';

import 'package:teampilot_tree_sitter/teampilot_tree_sitter.dart';
import 'package:test/test.dart';

void main() {
  test('parses json and captures string', () {
    final lang = TsLanguage.json();
    final parser = TsParser()..setLanguage(lang);
    final bytes = utf8.encode('{"a": 1}');
    final tree = parser.parseUtf8(Uint8List.fromList(bytes));
    final query = TsQuery(lang, '(string) @string');
    final caps = query.captures(tree, startByte: 0, endByte: bytes.length);
    expect(caps.any((c) => c.name == 'string'), isTrue);

    query.dispose();
    tree.dispose();
    parser.dispose();
  });
}
