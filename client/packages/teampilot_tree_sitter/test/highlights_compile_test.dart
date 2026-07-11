import 'dart:io';

import 'package:teampilot_tree_sitter/teampilot_tree_sitter.dart';
import 'package:test/test.dart';

// Compiles each app-shipped highlights.scm against its bundled grammar. A query
// referencing a node type or field the grammar does not define makes
// `TsQuery` throw, so this guards the LanguageRegistry packs from shipping
// broken query assets (which would break a worker session on file open).
//
// Tests run with CWD = the package dir; the assets live in the client app.
const _assetsRoot = '../../assets/editor_languages';

final _packs = <String, TsLanguage Function()>{
  'json': TsLanguage.json,
  'dart': TsLanguage.dart,
  'yaml': TsLanguage.yaml,
  'markdown': TsLanguage.markdown,
  'python': TsLanguage.python,
  'rust': TsLanguage.rust,
  'typescript': TsLanguage.typescript,
  'bash': TsLanguage.bash,
  'xml': TsLanguage.xml,
  'toml': TsLanguage.toml,
  'css': TsLanguage.css,
};

void main() {
  _packs.forEach((id, language) {
    test('compiles_${id}_highlights', () {
      final file = File('$_assetsRoot/$id/highlights.scm');
      expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
      final source = file.readAsStringSync();
      final query = TsQuery(language(), source);
      addTearDown(query.dispose);
    });
  });
}
