import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/chat/launch/staging/manifest/apply_plan.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/work_path_projector.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/work_plane_applier.dart';
import 'package:teampilot/services/storage/windows_cli_runtime_junction.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('copyTree of provided install dir becomes symlink', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeString('/h/plugins/installed/foo/a.txt', 'A');
    await workFs.ensureDir('/w/plugins/installed/foo');
    final manifest = LaunchManifest()
      ..copyTree(
        source: '/h/plugins/installed/foo',
        destination: '/w/sessions/pool/foo',
      );
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/h',
      workRoot: '/w',
    );
    expect(built.providedLinks, 1);
    expect(built.plan.ops, hasLength(1));
    final op = built.plan.ops.single as ApplySymlink;
    expect(op.linkPath, '/w/sessions/pool/foo');
    expect(op.target, '/w/plugins/installed/foo');
  });

  test('copyTree when work dir missing becomes hashed tree', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeBytes('/h/plugins/installed/foo/bin.dat', [0, 1, 255]);
    final manifest = LaunchManifest()
      ..copyTree(
        source: '/h/plugins/installed/foo',
        destination: '/w/sessions/pool/foo',
      );
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/h',
      workRoot: '/w',
    );
    expect(built.providedLinks, 0);
    final tree = built.plan.ops.whereType<ApplyTree>().single;
    expect(tree.dest, '/w/sessions/pool/foo');
    expect(tree.entries.single.rel, 'bin.dat');
    final bytes = await built.blobs.open(tree.entries.single.sha256);
    expect(bytes, [0, 1, 255]);
  });

  test('provided copyTree is materialized when later op mutates it', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeString('/h/plugins/installed/foo/a.txt', 'A');
    await workFs.ensureDir('/w/plugins/installed/foo');
    final manifest = LaunchManifest()
      ..copyTree(source: '/h/plugins/installed/foo', destination: '/w/sess/foo')
      ..writeFile('/w/sess/foo/stamp.json', '{}');

    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/h',
      workRoot: '/w',
    );

    expect(built.providedLinks, 0);
    expect(built.plan.ops.whereType<ApplySymlink>(), isEmpty);
    expect(built.plan.ops.whereType<ApplyTree>(), hasLength(1));
    expect(built.plan.ops.whereType<ApplyWriteInline>(), hasLength(1));
  });

  test('same path string different file bytes is not provided', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeString('/tp/a.txt', 'local');
    await workFs.writeString('/tp/a.txt', 'remote');
    final manifest = LaunchManifest()
      ..copyFile(source: '/tp/a.txt', destination: '/tp/sess/a.txt');
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/tp',
      workRoot: '/tp',
    );
    expect(built.providedLinks, 0);
    expect(built.plan.ops.single, isA<ApplyWriteBlob>());
  });

  test('writeFile at 4096 stays inline; 4097 is blob', () async {
    final fs = InMemoryFilesystem();
    final manifest = LaunchManifest()
      ..writeFile('/w/small.txt', 'a' * 4096)
      ..writeFile('/w/big.txt', 'a' * 4097);
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: fs,
      workFs: fs,
      homeRoot: '/w',
      workRoot: '/w',
    );
    expect(built.plan.ops[0], isA<ApplyWriteInline>());
    expect(built.plan.ops[1], isA<ApplyWriteBlob>());
  });

  test('unprojectable symlink target fails staging', () async {
    final fs = InMemoryFilesystem();
    final manifest = LaunchManifest()
      ..symlink(linkPath: '/w/l', target: '/not/in/roots');
    expect(
      () => buildApplyPlan(
        manifest: manifest,
        sourceFs: fs,
        workFs: fs,
        homeRoot: '/h',
        workRoot: '/w',
      ),
      throwsStateError,
    );
  });

  test('unprojectable symlink to a directory becomes a hashed tree', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeBytes('/home/hhoa/.cursor/plugins/cache/plug.bin', [
      9,
      8,
      7,
    ]);
    final manifest = LaunchManifest()
      ..symlink(
        linkPath: '/w/sessions/s/runtime/cursor/home/.cursor/plugins/cache',
        target: '/home/hhoa/.cursor/plugins/cache',
      );
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/h',
      workRoot: '/w',
    );
    expect(built.providedLinks, 0);
    expect(built.plan.ops.whereType<ApplySymlink>(), isEmpty);
    final tree = built.plan.ops.whereType<ApplyTree>().single;
    expect(
      tree.dest,
      '/w/sessions/s/runtime/cursor/home/.cursor/plugins/cache',
    );
    expect(tree.entries.single.rel, 'plug.bin');
    expect(await built.blobs.open(tree.entries.single.sha256), [9, 8, 7]);
  });

  test(
    'projectable symlink whose target is missing on workFs is materialized',
    () async {
      final sourceFs = InMemoryFilesystem();
      final workFs = InMemoryFilesystem();
      const target =
          '/tp/identities-runtime/p/home/.cursor/agent-cli-state.json';
      const linkPath =
          '/tp/workspace/workspaces/ws/sessions/s/runtime/cursor/home/'
          '.cursor/agent-cli-state.json';
      await sourceFs.writeString(target, '{"hasShownAgentCommandTip":true}');
      final manifest = LaunchManifest()
        ..symlink(linkPath: linkPath, target: target);
      final built = await buildApplyPlan(
        manifest: manifest,
        sourceFs: sourceFs,
        workFs: workFs,
        homeRoot: '/tp',
        workRoot: '/tp',
      );
      expect(built.providedLinks, 0);
      expect(built.plan.ops.whereType<ApplySymlink>(), isEmpty);
      final op = built.plan.ops.single as ApplyWriteBlob;
      expect(op.path, linkPath);
      expect(
        await built.blobs.open(op.sha256),
        utf8.encode('{"hasShownAgentCommandTip":true}'),
      );
    },
  );

  test(
    'symlink to a workRoot path created in the same plan stays a link',
    () async {
      final sourceFs = InMemoryFilesystem();
      final workFs = InMemoryFilesystem();
      const catalog =
          '/tp/workspace/ws/sessions/s/runtime/cursor/home/.cursor/'
          '.teampilot-managed/teampilot-catalog';
      const linkPath =
          '/tp/workspace/ws/sessions/s/runtime/cursor/home/.cursor/skills/'
          'teampilot-catalog';
      final manifest = LaunchManifest()
        ..ensureDir(catalog)
        ..writeFile('$catalog/SKILL.md', '# catalog')
        ..symlink(linkPath: linkPath, target: catalog);
      final built = await buildApplyPlan(
        manifest: manifest,
        sourceFs: sourceFs,
        workFs: workFs,
        homeRoot: '/tp',
        workRoot: '/tp',
      );
      expect(built.providedLinks, 0);
      final op = built.plan.ops.whereType<ApplySymlink>().single;
      expect(op.linkPath, linkPath);
      expect(op.target, catalog);
      expect(built.plan.ops.whereType<ApplyWriteInline>().map((e) => e.path), [
        '$catalog/SKILL.md',
      ]);
    },
  );

  test('symlink to a child of a plan copyTree dest stays a link', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    const installed = '/tp/plugins/installed/superpowers';
    const plugin =
        '/tp/workspace/ws/sessions/s/runtime/cursor/plugins/'
        'anthropics__claude-plugins-official__superpowers';
    const skills = '$plugin/skills';
    const linkPath =
        '/tp/workspace/ws/sessions/s/runtime/cursor/home/.cursor/skills/'
        'superpowers';
    await sourceFs.writeString('$installed/skills/x/SKILL.md', '# x');
    final manifest = LaunchManifest()
      ..copyTree(source: installed, destination: plugin)
      ..symlink(linkPath: linkPath, target: skills);
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/tp',
      workRoot: '/tp',
    );
    final op = built.plan.ops.whereType<ApplySymlink>().single;
    expect(op.linkPath, linkPath);
    expect(op.target, skills);
  });

  test('symlink to a child of a plan overlay symlink stays a link', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    const installed = '/tp/plugins/installed/superpowers';
    const plugin =
        '/tp/workspace/ws/sessions/s/runtime/cursor/plugins/'
        'anthropics__claude-plugins-official__superpowers';
    const skills = '$plugin/skills';
    const linkPath =
        '/tp/workspace/ws/sessions/s/runtime/cursor/home/.cursor/skills/'
        'superpowers';
    await sourceFs.writeString('$installed/skills/x/SKILL.md', '# x');
    final manifest = LaunchManifest()
      ..symlink(linkPath: plugin, target: installed)
      ..symlink(linkPath: linkPath, target: skills);
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/tp',
      workRoot: '/tp',
    );
    expect(
      built.plan.ops.whereType<ApplySymlink>().map((e) => e.linkPath),
      contains(linkPath),
    );
    expect(
      built.plan.ops.whereType<ApplySymlink>().map((e) => e.target),
      contains(skills),
    );
  });

  test(
    'projectable symlink whose target exists on workFs stays a provided link',
    () async {
      final fs = InMemoryFilesystem();
      const target =
          '/tp/identities-runtime/p/home/.cursor/agent-cli-state.json';
      const linkPath =
          '/tp/workspace/workspaces/ws/sessions/s/runtime/cursor/home/'
          '.cursor/agent-cli-state.json';
      await fs.writeString(target, '{"hasShownAgentCommandTip":true}');
      final manifest = LaunchManifest()
        ..symlink(linkPath: linkPath, target: target);
      final built = await buildApplyPlan(
        manifest: manifest,
        sourceFs: fs,
        workFs: fs,
        homeRoot: '/tp',
        workRoot: '/tp',
      );
      expect(built.providedLinks, 1);
      final op = built.plan.ops.single as ApplySymlink;
      expect(op.linkPath, linkPath);
      expect(op.target, target);
    },
  );

  test('dangling workRoot cache file symlink is kept for first fill', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    const cache =
        '/tp/workspace/cache/cli/cursor/cursor-account2/statsig-cache.json';
    const linkPath =
        '/tp/workspace/ws/sessions/s/runtime/cursor/home/.cursor/'
        'statsig-cache.json';
    final manifest = LaunchManifest()
      ..ensureDir('/tp/workspace/cache/cli/cursor/cursor-account2')
      ..symlink(linkPath: linkPath, target: cache);
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/tp',
      workRoot: '/tp',
    );
    final op = built.plan.ops.whereType<ApplySymlink>().single;
    expect(op.linkPath, linkPath);
    expect(op.target, cache);
  });

  test('unprojectable symlink to a file becomes a blob write', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeBytes('/home/alice/.claude.json', [0, 1, 255]);
    final manifest = LaunchManifest()
      ..symlink(
        linkPath: '/w/home/.claude.json',
        target: '/home/alice/.claude.json',
      );
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/h',
      workRoot: '/w',
    );
    expect(built.plan.ops.single, isA<ApplyWriteBlob>());
    final op = built.plan.ops.single as ApplyWriteBlob;
    expect(op.path, '/w/home/.claude.json');
    expect(await built.blobs.open(op.sha256), [0, 1, 255]);
  });

  test(
    'copyTree into Windows CLI runtime home identity-projects outside workRoot',
    () async {
      final ctx = p.Context(style: p.Style.windows);
      final sourceFs = InMemoryFilesystem(pathContext: ctx);
      final workFs = InMemoryFilesystem(pathContext: ctx);
      const workRoot = r'C:\tp\app-data';
      final physical = ctx.join(
        r'C:\Users\runneradmin\AppData\Local\com.hhoa.teampilot',
        WindowsCliRuntimeJunction.runtimeHomesDirName,
        'cursor',
        '5adc1e2fd5ca4d61',
        'home',
      );
      await sourceFs.writeString(ctx.join(physical, '.cursor', 'a.txt'), 'x');
      final manifest = LaunchManifest()
        ..copyTree(source: physical, destination: physical);
      final built = await buildApplyPlan(
        manifest: manifest,
        sourceFs: sourceFs,
        workFs: workFs,
        homeRoot: workRoot,
        workRoot: workRoot,
      );
      final tree = built.plan.ops.whereType<ApplyTree>().single;
      expect(tree.dest, ctx.normalize(physical));
      expect(tree.entries.single.rel, ctx.join('.cursor', 'a.txt'));
    },
  );

  test('copyTree source missing on disk becomes ensureDir of dest', () async {
    final ctx = p.Context(style: p.Style.windows);
    final sourceFs = InMemoryFilesystem(pathContext: ctx);
    final workFs = InMemoryFilesystem(pathContext: ctx);
    const workRoot = r'C:\tp\app-data';
    final canonical = ctx.join(
      workRoot,
      r'workspace\workspaces\ws\sessions\s\runtime\cursor\home',
    );
    final physical = ctx.join(
      r'C:\Users\RUNNER~1\AppData\Local\com.hhoa.teampilot',
      WindowsCliRuntimeJunction.runtimeHomesDirName,
      'cursor',
      '8f573239deadbeef',
      'home',
    );
    final manifest = LaunchManifest()
      ..copyTree(source: canonical, destination: physical);
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: workRoot,
      workRoot: workRoot,
    );
    expect(built.plan.ops.single, isA<ApplyEnsureDir>());
    expect(
      (built.plan.ops.single as ApplyEnsureDir).path,
      ctx.normalize(physical),
    );
  });

  test(
    'Windows home to posix work plane keeps posix workRoot for apply',
    () async {
      final windows = p.Context(style: p.Style.windows);
      final posix = p.Context(style: p.Style.posix);
      final sourceFs = InMemoryFilesystem(pathContext: windows);
      final workFs = InMemoryFilesystem(pathContext: posix);
      const homeRoot = r'C:\Users\runner\AppData\Local\teampilot';
      const workRoot = '/home/testuser/.local/share/com.hhoa.teampilot';
      const settings =
          '$workRoot/workspace/workspaces/ws/sessions/s/runtime/'
          'developer/claude/settings/developer.json';
      final manifest = LaunchManifest()..writeFile(settings, '{"hooks":[]}');
      final built = await buildApplyPlan(
        manifest: manifest,
        sourceFs: sourceFs,
        workFs: workFs,
        homeRoot: homeRoot,
        workRoot: workRoot,
      );
      expect(built.plan.workRoot, workRoot);
      await WorkPlaneApplier(
        fs: workFs,
        blobs: built.blobs,
        workRoot: workRoot,
      ).apply(built.plan);
      expect(await workFs.readString(settings), '{"hooks":[]}');
    },
  );

  test(
    'posix work plane projects Windows-mangled work symlink targets',
    () async {
      final windows = p.Context(style: p.Style.windows);
      final posix = p.Context(style: p.Style.posix);
      final sourceFs = InMemoryFilesystem(pathContext: windows);
      final workFs = InMemoryFilesystem(pathContext: posix);
      const homeRoot = r'C:\Users\runner\AppData\Local\teampilot';
      const workRoot = '/home/testuser/.local/share/com.hhoa.teampilot';
      const agents = '$workRoot/cli-defaults/claude/agents';
      const mangledAgents =
          r'\home\testuser\.local\share\com.hhoa.teampilot\cli-defaults\claude\agents';
      const sessionAgents =
          '$workRoot/workspace/workspaces/ws/sessions/s/runtime/claude/agents';
      final manifest = LaunchManifest()
        ..ensureDir(agents)
        ..symlink(linkPath: sessionAgents, target: mangledAgents);
      final built = await buildApplyPlan(
        manifest: manifest,
        sourceFs: sourceFs,
        workFs: workFs,
        homeRoot: homeRoot,
        workRoot: workRoot,
      );
      final link = built.plan.ops.whereType<ApplySymlink>().single;
      expect(link.linkPath, sessionAgents);
      expect(link.target, agents);
    },
  );
}
