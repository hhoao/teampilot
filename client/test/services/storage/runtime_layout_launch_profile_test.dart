import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('identity runtime paths key by identity id under identities-runtime', () {
    final fs = InMemoryFilesystem();
    final ctx = fs.pathContext;
    final layout = RuntimeLayout(teampilotRoot: '/root', fs: fs);
    expect(
      layout.identitiesRuntimeDir,
      ctx.join('/root', 'identities-runtime'),
    );
    expect(
      layout.identityRuntimeDir('coding'),
      ctx.join('/root', 'identities-runtime', 'coding'),
    );
    expect(
      layout.identityToolDir('coding', 'claude'),
      ctx.join('/root', 'identities-runtime', 'coding', 'claude'),
    );
    expect(
      layout.identitySessionCounterFile('coding'),
      ctx.join('/root', 'identities-runtime', 'coding', 'session-counter.json'),
    );
  });
}
