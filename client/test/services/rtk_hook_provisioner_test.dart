import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/rtk_hook_provisioner.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  test('provisionMemberToolDir writes hook script', () async {
    final fs = InMemoryFilesystem();
    final memberDir = fs.pathContext.join('/data', 'flashskyai');
    await fs.ensureDir(memberDir);

    final provisioner = RtkHookProvisioner(
      fs: fs,
      loadHookScript: () async => '#!/bin/bash\necho rtk\n',
    );

    final scriptPath = await provisioner.provisionMemberToolDir(memberDir);
    expect(scriptPath, endsWith('rtk-rewrite.sh'));

    final content = await fs.readString(scriptPath);
    expect(content, contains('rtk'));

    expect(
      provisioner.hookCommandForPath(scriptPath),
      'bash "${scriptPath.replaceAll('"', r'\"')}"',
    );
  });
}
