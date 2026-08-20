import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_plugin_runtime_tree.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_capability.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  group('CursorPluginRuntimeTree', () {
    test('keeps plugin root inside dest and hides git/node_modules', () async {
      final fs = InMemoryFilesystem();
      const source = '/pool/superpowers';
      const dest = '/cfg/plugins/local/superpowers';
      await fs.writeString(
        '$source/.cursor-plugin/plugin.json',
        '{"name":"superpowers"}',
      );
      await fs.writeString('$source/skills/brainstorming/SKILL.md', '# skill');
      await fs.writeString('$source/.git/HEAD', 'ref: refs/heads/main');
      await fs.writeString('$source/node_modules/leftpad/index.js', 'exports');
      await fs.writeString('$source/.mcp.json', '{}');

      await CursorPluginRuntimeTree.materialize(
        fs: fs,
        sourceRoot: source,
        destRoot: dest,
        paths: cursorPluginManifestPaths,
      );

      expect((await fs.stat(dest)).isDirectory, isTrue);
      expect(await fs.readSymlinkTarget(dest), isNull);
      expect(
        await fs.readString('$dest/.cursor-plugin/plugin.json'),
        contains('superpowers'),
      );
      expect(await fs.readString('$dest/.mcp.json'), '{}');
      expect(await fs.readSymlinkTarget('$dest/skills'), '$source/skills');
      expect(
        await fs.readString('$dest/skills/brainstorming/SKILL.md'),
        '# skill',
      );
      expect((await fs.stat('$dest/.git')).exists, isFalse);
      expect((await fs.stat('$dest/node_modules')).exists, isFalse);
    });
  });
}
