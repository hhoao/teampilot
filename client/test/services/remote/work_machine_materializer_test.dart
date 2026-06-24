import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/remote/materialization_manifest.dart';
import 'package:teampilot/services/remote/work_machine_materializer.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/in_memory_filesystem.dart';

/// InMemoryFilesystem that counts file-content writes (ancestry copies), so the
/// hash-skip behavior is observable.
class _CountingFs extends InMemoryFilesystem {
  int writeBytesCount = 0;
  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    writeBytesCount++;
    await super.writeBytes(path, bytes);
  }
}

WorkMachineMaterializer _materializer(InMemoryFilesystem homeFs, _CountingFs workFs) =>
    WorkMachineMaterializer(
      homeFs: homeFs,
      homeRoot: '/home',
      workFs: workFs,
      machineRoot: '/remote',
      manifest: MaterializationManifest(fs: workFs, machineRoot: '/remote'),
    );

void main() {
  test('materializes ancestry to machineRoot and closes inheritance in-root',
      () async {
    final homeFs = InMemoryFilesystem();
    await homeFs.writeString('/home/cli-defaults/claude/agents/x.md', 'A');
    final workFs = _CountingFs();
    final m = _materializer(homeFs, workFs);

    await m.reconcile(tools: {'claude'}, workspaceId: 'w1');

    // ① ancestry copied under the work machine root
    expect(
      (await workFs.stat('/remote/cli-defaults/claude/agents/x.md')).isFile,
      isTrue,
    );

    // ② session-runtime inherited symlink resolves *within* machineRoot
    await m.ensureSessionInheritance(
      workspaceId: 'w1',
      sessionId: 's1',
      tool: 'claude',
      memberId: 'm1',
    );
    final work = RuntimeLayout(teampilotRoot: '/remote', fs: workFs);
    final sessionAgents = workFs.pathContext.join(
      work.sessionRuntimeToolDir('w1', 's1', 'claude', memberId: 'm1'),
      'agents',
    );
    final target = await workFs.readSymlinkTarget(sessionAgents);
    expect(target, isNotNull);
    expect(target, startsWith('/remote')); // not /home
  });

  test('second reconcile with unchanged content skips re-copy (manifest hit)',
      () async {
    final homeFs = InMemoryFilesystem();
    await homeFs.writeString('/home/cli-defaults/claude/agents/x.md', 'A');
    await homeFs.writeString('/home/cli-defaults/claude/agents/y.md', 'B');
    final workFs = _CountingFs();
    final m = _materializer(homeFs, workFs);

    await m.reconcile(tools: {'claude'}, workspaceId: 'w1');
    expect(workFs.writeBytesCount, 2);

    await m.reconcile(tools: {'claude'}, workspaceId: 'w1');
    expect(workFs.writeBytesCount, 2); // no re-copy
  });

  test('changing one file re-copies only that file', () async {
    final homeFs = InMemoryFilesystem();
    await homeFs.writeString('/home/cli-defaults/claude/agents/x.md', 'A');
    await homeFs.writeString('/home/cli-defaults/claude/agents/y.md', 'B');
    final workFs = _CountingFs();
    final m = _materializer(homeFs, workFs);

    await m.reconcile(tools: {'claude'}, workspaceId: 'w1');
    expect(workFs.writeBytesCount, 2);

    await homeFs.writeString('/home/cli-defaults/claude/agents/x.md', 'A-changed');
    await m.reconcile(tools: {'claude'}, workspaceId: 'w1');
    expect(workFs.writeBytesCount, 3); // only x re-copied
  });
}
