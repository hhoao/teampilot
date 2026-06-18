import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/codex/codex_project_trust_toml.dart';

void main() {
  group('CodexProjectTrustToml', () {
    test('appends trusted workspace block for working directory', () {
      const cwd = '/home/user/Document/testmixed';
      final result = CodexProjectTrustToml.applyTrustedDirectories(
        'model = "gpt-5"\n',
        [cwd],
      );
      expect(
        result,
        contains('[workspaces."/home/user/Document/testmixed"]'),
      );
      expect(result, contains('trust_level = "trusted"'));
    });

    test('skips paths already marked trusted in toml', () {
      const cwd = '/home/user/proj';
      const existing = '''
[workspaces."/home/user/proj"]
trust_level = "trusted"
model = "m"
''';
      final result = CodexProjectTrustToml.applyTrustedDirectories(
        existing,
        [cwd],
      );
      expect(result.split('[workspaces."/home/user/proj"]').length, 2);
    });

    test('merges multiple directories', () {
      final result = CodexProjectTrustToml.applyTrustedDirectories('', [
        '/a/one',
        '/a/two',
      ]);
      expect(result, contains('[workspaces."/a/one"]'));
      expect(result, contains('[workspaces."/a/two"]'));
    });
  });
}
