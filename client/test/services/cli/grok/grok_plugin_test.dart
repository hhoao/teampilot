import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/plugins/grok_plugin_projector.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('projects a neutral bundle onto the Grok plugin layout', () async {
    final fs = InMemoryFilesystem();
    await fs.ensureDir('/pool/my-plugin/.plugin');
    await fs.atomicWrite(
      '/pool/my-plugin/.plugin/plugin.json',
      '{"name":"my-plugin","version":"1.2.3"}',
    );
    await fs.atomicWrite(
      '/pool/my-plugin/.plugin/.mcp.json',
      '{"mcpServers":{"docs":{"command":"npx"}}}',
    );
    await fs.atomicWrite(
      '/pool/my-plugin/.plugin/hooks.json',
      '{"hooks":{"SessionStart":[]}}',
    );
    await fs.atomicWrite('/pool/my-plugin/skills/review/SKILL.md', '# review');
    await fs.atomicWrite('/pool/my-plugin/commands/fix.md', '# fix');

    final name = await GrokPluginProjector.project(
      fs: fs,
      bundleDir: '/pool/my-plugin',
      targetDir: '/cfg/plugins/my-plugin',
    );

    expect(name, 'my-plugin');
    expect(
      await fs.readString('/cfg/plugins/my-plugin/plugin.json'),
      contains('my-plugin'),
    );
    expect(
      await fs.readString('/cfg/plugins/my-plugin/.plugin/plugin.json'),
      contains('my-plugin'),
    );
    expect(
      await fs.readString('/cfg/plugins/my-plugin/.mcp.json'),
      contains('mcpServers'),
    );
    expect(
      await fs.readString('/cfg/plugins/my-plugin/hooks/hooks.json'),
      contains('SessionStart'),
    );
    expect(
      await fs.readString('/cfg/plugins/my-plugin/skills/review/SKILL.md'),
      '# review',
    );
    expect(
      await fs.readString('/cfg/plugins/my-plugin/commands/fix.md'),
      '# fix',
    );
  });

  test('rejects traversal directory names', () {
    expect(GrokPluginProjector.isSafeDirName('..'), isFalse);
    expect(GrokPluginProjector.isSafeDirName('a/b'), isFalse);
    expect(GrokPluginProjector.isSafeDirName('my-plugin'), isTrue);
  });
}
