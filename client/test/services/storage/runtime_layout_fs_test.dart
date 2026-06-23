import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/in_memory_filesystem.dart';

/// Proves RuntimeLayout's inherit/accessibility logic runs through the
/// Filesystem abstraction (listDir / readSymlinkTarget / resolveSymlink) with a
/// non-Local filesystem — i.e. no raw dart:io that would crash a remote ctx.
void main() {
  test('identity inherits app tool layout via Filesystem (idempotent)', () async {
    final fs = InMemoryFilesystem();
    final layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);

    await layout.ensureAppToolLayout('flashskyai');
    await layout.ensureIdentityInheritsApp('id1', 'flashskyai');
    // Re-run: _inheritLinkCurrent (readSymlinkTarget) + _inheritedPathIsAccessible
    // (listDir) decide it's already linked — must not throw and stay stable.
    await layout.ensureIdentityInheritsApp('id1', 'flashskyai');

    final identityDir = layout.identityToolDir('id1', 'flashskyai');
    expect((await fs.stat(identityDir)).exists, isTrue);
  });
}
