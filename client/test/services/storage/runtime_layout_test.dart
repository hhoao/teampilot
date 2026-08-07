import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/in_memory_filesystem.dart';

final _posixPath = p.Context(style: p.Style.posix);

class _NoSymlinkFilesystem extends InMemoryFilesystem {
  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    return false;
  }
}

void main() {
  const workspaceId = 'proj-1';

  group('RuntimeLayout path computation', () {
    final layout = RuntimeLayout(
      teampilotRoot: '/tp',
      fs: InMemoryFilesystem(),
    );

    test('appToolRoot is cli-defaults/<tool>', () {
      expect(layout.appToolRoot('flashskyai'), '/tp/cli-defaults/flashskyai');
      expect(layout.appToolRoot('claude'), '/tp/cli-defaults/claude');
    });

    test('identityToolDir is identities-runtime/<id>/<tool>', () {
      expect(
        layout.identityToolDir('team-a', 'flashskyai'),
        '/tp/identities-runtime/team-a/flashskyai',
      );
    });

    test('sessionRuntimeToolDir nests under workspace session runtime', () {
      expect(
        layout.sessionRuntimeToolDir(workspaceId, 'sess-1', 'flashskyai'),
        '/tp/workspace/workspaces/proj-1/sessions/sess-1/runtime/flashskyai',
      );
    });

    test(
      'transcriptSearchRoots returns app + team + workspace + session for each tool',
      () {
        final roots = layout.transcriptSearchRoots(
          workspaceId: workspaceId,
          sessionId: 'sess-1',
          profileId: 'team-a',
        );
        expect(roots, [
          for (final tool in runtimeLayoutDefaultTools)
            '/tp/cli-defaults/$tool',
          for (final tool in runtimeLayoutDefaultTools)
            '/tp/identities-runtime/team-a/$tool',
          for (final tool in runtimeLayoutDefaultTools)
            '/tp/workspace/workspaces/proj-1/config/$tool',
          for (final tool in runtimeLayoutDefaultTools)
            '/tp/workspace/workspaces/proj-1/sessions/sess-1/runtime/$tool',
        ]);
      },
    );

    test(
      'transcriptSearchRoots with memberId includes member + shared session dirs',
      () {
        final roots = layout.transcriptSearchRoots(
          workspaceId: workspaceId,
          sessionId: 'sess-1',
          profileId: 'team-a',
          memberId: 'team-lead',
          tools: const ['claude'],
        );
        expect(roots, [
          '/tp/cli-defaults/claude',
          '/tp/identities-runtime/team-a/claude',
          '/tp/workspace/workspaces/proj-1/config/claude',
          // Mixed nested CONFIG_DIR, then native shared CONFIG_DIR.
          '/tp/workspace/workspaces/proj-1/sessions/sess-1/runtime/team-lead/claude',
          '/tp/workspace/workspaces/proj-1/sessions/sess-1/runtime/claude',
        ]);
      },
    );

    test('transcriptSearchRoots omits session layer when sessionId empty', () {
      final roots = layout.transcriptSearchRoots(
        workspaceId: workspaceId,
        sessionId: '',
        profileId: 'team-a',
        tools: const ['flashskyai'],
      );
      expect(roots, [
        '/tp/cli-defaults/flashskyai',
        '/tp/identities-runtime/team-a/flashskyai',
        '/tp/workspace/workspaces/proj-1/config/flashskyai',
      ]);
    });

    test(
      'appFlashskyaiLlmConfigFile points at cli-defaults llm_config.json',
      () {
        expect(
          layout.appFlashskyaiLlmConfigFile,
          '/tp/cli-defaults/flashskyai/llm_config.json',
        );
      },
    );
  });

  group('WorkspaceLayout workspace paths', () {
    final layout = RuntimeLayout(
      teampilotRoot: '/tp',
      fs: InMemoryFilesystem(),
    );

    test('workspace.workspacesDir is workspace/workspaces', () {
      expect(layout.workspace.workspacesDir, '/tp/workspace/workspaces');
    });

    test('workspaceDir nests under workspace/workspaces/<workspaceId>', () {
      expect(
        layout.workspace.workspaceDir('proj'),
        '/tp/workspace/workspaces/proj',
      );
    });

    test('workspaceConfigToolDir nests tool under workspace config', () {
      expect(
        layout.workspaceConfigToolDir('proj', 'claude'),
        '/tp/workspace/workspaces/proj/config/claude',
      );
    });

    test('sessionRuntimeToolDir nests session and tool', () {
      expect(
        layout.sessionRuntimeToolDir('proj', 'sess', 'claude'),
        '/tp/workspace/workspaces/proj/sessions/sess/runtime/claude',
      );
    });

    test('trims workspaceId sessionId and tool like team helpers', () {
      expect(
        layout.workspace.workspaceDir('  proj  '),
        layout.workspace.workspaceDir('proj'),
      );
      expect(
        layout.workspaceConfigToolDir(' proj ', ' claude '),
        layout.workspaceConfigToolDir('proj', 'claude'),
      );
      expect(
        layout.sessionRuntimeToolDir(' proj ', ' sess ', ' claude '),
        layout.sessionRuntimeToolDir('proj', 'sess', 'claude'),
      );
    });

    test('uses filesystem path context from injected fs', () {
      final windowsLayout = RuntimeLayout(
        teampilotRoot: r'C:\tp',
        fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.windows)),
      );
      expect(
        windowsLayout.sessionRuntimeToolDir('proj', 'sess', 'claude'),
        r'C:\tp\workspace\workspaces\proj\sessions\sess\runtime\claude',
      );
    });
  });

  group('workspaceBucketForPrimaryPath', () {
    test('POSIX paths slugify directly', () {
      expect(
        RuntimeLayout.workspaceBucketForPrimaryPath('/home/hhoa/agent'),
        '-home-hhoa-agent',
      );
    });

    test('Windows drive paths map to /mnt/<drive>/...', () {
      expect(
        RuntimeLayout.workspaceBucketForPrimaryPath(
          r'D:\a\teampilot\teampilot\client',
        ),
        '-mnt-d-a-teampilot-teampilot-client',
      );
      expect(
        RuntimeLayout.workspaceBucketForPrimaryPath(r'C:\Users\hhoa\agent'),
        '-mnt-c-Users-hhoa-agent',
      );
    });

    test('empty path returns empty bucket', () {
      expect(RuntimeLayout.workspaceBucketForPrimaryPath(''), '');
    });
  });

  group('RuntimeLayout.ensure*', () {
    late Directory base;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('runtime_layout_');
    });

    tearDown(() async {
      if (await base.exists()) {
        await base.delete(recursive: true);
      }
    });

    test('ensureAppToolLayout creates app tool dir', () async {
      final layout = RuntimeLayout(
        teampilotRoot: base.path,
        fs: LocalFilesystem(),
      );
      await layout.ensureAppToolLayout('flashskyai');
      expect(
        await Directory(layout.appToolRoot('flashskyai')).exists(),
        isTrue,
      );
    });

    test('ensureIdentityInheritsApp symlinks agents from app level', () async {
      final layout = RuntimeLayout(
        teampilotRoot: base.path,
        fs: LocalFilesystem(),
      );
      await layout.ensureAppToolLayout('flashskyai');
      final appAgents = Directory(
        p.join(layout.appToolRoot('flashskyai'), 'agents'),
      );
      await appAgents.create(recursive: true);
      await File(p.join(appAgents.path, 'demo.md')).writeAsString('# demo');

      await layout.ensureIdentityInheritsApp('team-a', 'flashskyai');

      final teamAgents = p.join(
        layout.identityToolDir('team-a', 'flashskyai'),
        'agents',
      );
      expect(_inheritedPathExists(teamAgents), isTrue);
      if (Link(teamAgents).existsSync()) {
        expect(Link(teamAgents).targetSync(), appAgents.path);
      }

      expect(
        await File(p.join(teamAgents, 'demo.md')).readAsString(),
        '# demo',
      );

      final teamSkills = p.join(
        layout.identityToolDir('team-a', 'flashskyai'),
        'skills',
      );
      expect(
        Link(teamSkills).existsSync() || Directory(teamSkills).existsSync(),
        isFalse,
        reason: 'team skills/ must not be an inherited symlink or dir',
      );
    });

    test(
      'ensureSessionRuntimeInheritsIdentity chains agents app → team → session symlinks',
      () async {
        final layout = RuntimeLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('flashskyai');
        final appAgents = Directory(
          p.join(layout.appToolRoot('flashskyai'), 'agents'),
        );
        await appAgents.create(recursive: true);
        await File(
          p.join(appAgents.path, 'README.md'),
        ).writeAsString('top-level');

        await layout.ensureSessionRuntimeInheritsIdentity(
          workspaceId,
          'sess-1',
          'team-a',
          'flashskyai',
        );

        final sessionAgents = _posixPath.join(
          layout.sessionRuntimeToolDir(workspaceId, 'sess-1', 'flashskyai'),
          'agents',
        );
        expect(_inheritedPathExists(sessionAgents), isTrue);
        expect(
          await File(p.join(sessionAgents, 'README.md')).readAsString(),
          'top-level',
        );

        final sessionSkills = _posixPath.join(
          layout.sessionRuntimeToolDir(workspaceId, 'sess-1', 'flashskyai'),
          'skills',
        );
        expect(
          Link(sessionSkills).existsSync(),
          isFalse,
          reason: 'session skills/ must not be an inherited symlink',
        );
      },
    );

    test('symlink failure falls back to copy', () async {
      final fs = _NoSymlinkFilesystem();
      final layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
      await layout.ensureAppToolLayout('flashskyai');
      final appAgents = _posixPath.join(
        layout.appToolRoot('flashskyai'),
        'agents',
      );
      await fs.ensureDir(appAgents);
      await fs.writeString(_posixPath.join(appAgents, 'demo.md'), 'hello');

      await layout.ensureIdentityInheritsApp('team-a', 'flashskyai');

      final teamAgentsPath = _posixPath.join(
        layout.identityToolDir('team-a', 'flashskyai'),
        'agents',
      );
      expect(fs.symlinks.containsKey(teamAgentsPath), isFalse);
      expect(fs.directories.contains(teamAgentsPath), isTrue);
      expect(
        await fs.readString(_posixPath.join(teamAgentsPath, 'demo.md')),
        'hello',
      );
    });

    test(
      'concurrent ensureIdentityInheritsApp does not throw PathExistsException',
      () async {
        final layout = RuntimeLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('flashskyai');

        await Future.wait([
          layout.ensureIdentityInheritsApp('team-a', 'flashskyai'),
          layout.ensureIdentityInheritsApp('team-a', 'flashskyai'),
          layout.ensureIdentityInheritsApp('team-a', 'flashskyai'),
        ]);

        final teamAgents = p.join(
          layout.identityToolDir('team-a', 'flashskyai'),
          'agents',
        );
        expect(_inheritedPathExists(teamAgents), isTrue);
      },
    );

    test(
      'concurrent ensureSessionRuntimeInheritsIdentity for multiple sessions succeeds',
      () async {
        final layout = RuntimeLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('flashskyai');

        await Future.wait([
          layout.ensureSessionRuntimeInheritsIdentity(
            workspaceId,
            'member-1',
            'team-a',
            'flashskyai',
          ),
          layout.ensureSessionRuntimeInheritsIdentity(
            workspaceId,
            'member-2',
            'team-a',
            'flashskyai',
          ),
          layout.ensureSessionRuntimeInheritsIdentity(
            workspaceId,
            'member-3',
            'team-a',
            'flashskyai',
          ),
        ]);

        for (final sessionId in ['member-1', 'member-2', 'member-3']) {
          final sessionAgents = p.join(
            layout.sessionRuntimeToolDir(workspaceId, sessionId, 'flashskyai'),
            'agents',
          );
          expect(_inheritedPathExists(sessionAgents), isTrue);
        }
      },
    );

    test(
      'ensureSessionRuntimeInheritsIdentity tolerates existing team agents symlinks on Windows',
      () async {
        if (!Platform.isWindows) return;

        final fs = LocalFilesystem();
        final layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
        await layout.ensureAppToolLayout('claude');
        final appAgents = Directory(
          p.join(layout.appToolRoot('claude'), 'agents'),
        );
        await appAgents.create(recursive: true);
        await File(p.join(appAgents.path, 'probe.md')).writeAsString('ok');

        final teamAgents = p.join(
          layout.identityToolDir('team-a', 'claude'),
          'agents',
        );
        await Directory(p.dirname(teamAgents)).create(recursive: true);
        await Link(teamAgents).create(appAgents.path);
        await expectLater(fs.ensureDir(teamAgents), completes);

        await layout.ensureSessionRuntimeInheritsIdentity(
          workspaceId,
          'sess-1',
          'team-a',
          'claude',
        );

        final sessionAgents = p.join(
          layout.sessionRuntimeToolDir(workspaceId, 'sess-1', 'claude'),
          'agents',
        );
        expect(_inheritedPathExists(sessionAgents), isTrue);
        expect(
          await File(p.join(sessionAgents, 'probe.md')).readAsString(),
          'ok',
        );
      },
    );

    test('ensureWorkspaceConfigInheritsApp symlinks agents from app', () async {
      final layout = RuntimeLayout(
        teampilotRoot: base.path,
        fs: LocalFilesystem(),
      );
      await layout.ensureAppToolLayout('flashskyai');
      final appAgents = Directory(
        p.join(layout.appToolRoot('flashskyai'), 'agents'),
      );
      await appAgents.create(recursive: true);
      await File(p.join(appAgents.path, 'demo.md')).writeAsString('# demo');

      await layout.ensureWorkspaceConfigInheritsApp('proj-a', 'flashskyai');

      final workspaceAgents = p.join(
        layout.workspaceConfigToolDir('proj-a', 'flashskyai'),
        'agents',
      );
      expect(_inheritedPathExists(workspaceAgents), isTrue);
      if (Link(workspaceAgents).existsSync()) {
        expect(Link(workspaceAgents).targetSync(), appAgents.path);
      }
      expect(
        await File(p.join(workspaceAgents, 'demo.md')).readAsString(),
        '# demo',
      );

      final workspaceSkills = p.join(
        layout.workspaceConfigToolDir('proj-a', 'flashskyai'),
        'skills',
      );
      expect(
        Link(workspaceSkills).existsSync() ||
            Directory(workspaceSkills).existsSync(),
        isFalse,
        reason: 'workspace skills/ must not be an inherited symlink or dir',
      );
    });

    test(
      'ensureSessionInheritsOpencodePluginDeps links node_modules and package.json',
      () async {
        final layout = RuntimeLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('opencode');
        final app = layout.appToolRoot('opencode');
        await File(p.join(app, 'package.json')).writeAsString(
          '{"dependencies":{"@opencode-ai/plugin":"1.0.0"}}',
        );
        await Directory(
          p.join(app, 'node_modules', '@opencode-ai', 'plugin'),
        ).create(recursive: true);

        final sessionDir = layout.sessionRuntimeToolDir(
          workspaceId,
          'sess-oc',
          'opencode',
        );
        await Directory(sessionDir).create(recursive: true);
        await Directory(
          p.join(sessionDir, 'node_modules', 'old'),
        ).create(recursive: true);

        await layout.ensureSessionInheritsOpencodePluginDeps(
          workspaceId,
          'sess-oc',
        );

        final linkedNm = _posixPath.join(sessionDir, 'node_modules');
        final linkedPkg = _posixPath.join(sessionDir, 'package.json');
        expect(_inheritedPathExists(linkedNm), isTrue);
        expect(
          await Directory(
            p.join(linkedNm, '@opencode-ai', 'plugin'),
          ).exists(),
          isTrue,
        );
        expect(
          await File(linkedPkg).readAsString(),
          contains('@opencode-ai/plugin'),
        );
        expect(
          Directory(p.join(linkedNm, 'old')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'ensureSessionInheritsOpencodePluginDeps also inherits package-lock.json',
      () async {
        final layout = RuntimeLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('opencode');
        final app = layout.appToolRoot('opencode');
        await File(p.join(app, 'package.json')).writeAsString(
          '{"dependencies":{"@opencode-ai/plugin":"1.18.5"}}',
        );
        await File(p.join(app, 'package-lock.json')).writeAsString(
          '{"packages":{"":{"dependencies":{"@opencode-ai/plugin":"1.18.5"}}}}',
        );
        await Directory(
          p.join(app, 'node_modules', '@opencode-ai', 'plugin'),
        ).create(recursive: true);

        final sessionDir = layout.sessionRuntimeToolDir(
          workspaceId,
          'sess-oc-lock',
          'opencode',
        );
        await Directory(sessionDir).create(recursive: true);

        await layout.ensureSessionInheritsOpencodePluginDeps(
          workspaceId,
          'sess-oc-lock',
        );

        final linkedLock = p.join(sessionDir, 'package-lock.json');
        expect(await File(linkedLock).exists(), isTrue);
        expect(
          await File(linkedLock).readAsString(),
          contains('@opencode-ai/plugin'),
        );
      },
    );

    test(
      'ensureSessionInheritsOpencodePluginDeps inherits package-lock when package.json already linked',
      () async {
        final layout = RuntimeLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('opencode');
        final app = layout.appToolRoot('opencode');
        final pkgSource = p.join(app, 'package.json');
        await File(pkgSource).writeAsString(
          '{"dependencies":{"@opencode-ai/plugin":"1.18.5"}}',
        );
        await File(p.join(app, 'package-lock.json')).writeAsString(
          '{"packages":{"":{"dependencies":{"@opencode-ai/plugin":"1.18.5"}}}}',
        );
        await Directory(
          p.join(app, 'node_modules', '@opencode-ai', 'plugin'),
        ).create(recursive: true);

        final sessionDir = layout.sessionRuntimeToolDir(
          workspaceId,
          'sess-oc-relink',
          'opencode',
        );
        await Directory(sessionDir).create(recursive: true);
        await Link(p.join(sessionDir, 'package.json')).create(pkgSource);

        await layout.ensureSessionInheritsOpencodePluginDeps(
          workspaceId,
          'sess-oc-relink',
        );

        expect(
          await File(p.join(sessionDir, 'package-lock.json')).exists(),
          isTrue,
        );
        expect(
          await File(p.join(sessionDir, 'package-lock.json')).readAsString(),
          contains('@opencode-ai/plugin'),
        );
      },
    );

    test(
      'ensureSessionInheritsOpencodePluginDeps with memberId uses mixed-mode path',
      () async {
        final layout = RuntimeLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('opencode');
        final app = layout.appToolRoot('opencode');
        await File(p.join(app, 'package.json')).writeAsString(
          '{"dependencies":{"@opencode-ai/plugin":"1.0.0"}}',
        );
        await Directory(
          p.join(app, 'node_modules', '@opencode-ai', 'plugin'),
        ).create(recursive: true);

        final sessionDir = layout.sessionRuntimeToolDir(
          workspaceId,
          'sess-mixed',
          'opencode',
          memberId: 'coder-1',
        );
        await Directory(sessionDir).create(recursive: true);

        await layout.ensureSessionInheritsOpencodePluginDeps(
          workspaceId,
          'sess-mixed',
          memberId: 'coder-1',
        );

        final linkedNm = _posixPath.join(sessionDir, 'node_modules');
        final linkedPkg = _posixPath.join(sessionDir, 'package.json');
        expect(_inheritedPathExists(linkedNm), isTrue);
        expect(
          await Directory(
            p.join(linkedNm, '@opencode-ai', 'plugin'),
          ).exists(),
          isTrue,
        );
        expect(
          await File(linkedPkg).readAsString(),
          contains('@opencode-ai/plugin'),
        );
      },
    );

    test(
      'concurrent ensureSessionInheritsOpencodePluginDeps for multiple sessions succeeds',
      () async {
        final layout = RuntimeLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('opencode');
        final app = layout.appToolRoot('opencode');
        await File(p.join(app, 'package.json')).writeAsString(
          '{"dependencies":{"@opencode-ai/plugin":"1.0.0"}}',
        );
        await Directory(
          p.join(app, 'node_modules', '@opencode-ai', 'plugin'),
        ).create(recursive: true);

        await Future.wait([
          layout.ensureSessionInheritsOpencodePluginDeps(
            workspaceId,
            'sess-a',
          ),
          layout.ensureSessionInheritsOpencodePluginDeps(
            workspaceId,
            'sess-b',
          ),
          layout.ensureSessionInheritsOpencodePluginDeps(
            workspaceId,
            'sess-c',
          ),
        ]);

        for (final sessionId in ['sess-a', 'sess-b', 'sess-c']) {
          final sessionDir = layout.sessionRuntimeToolDir(
            workspaceId,
            sessionId,
            'opencode',
          );
          final linkedNm = p.join(sessionDir, 'node_modules');
          expect(_inheritedPathExists(linkedNm), isTrue);
          expect(
            await File(p.join(sessionDir, 'package.json')).readAsString(),
            contains('@opencode-ai/plugin'),
          );
        }
      },
    );

    test(
      'ensureSessionRuntimeInheritsWorkspace chains agents app → workspace → session',
      () async {
        final layout = RuntimeLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('flashskyai');
        final appAgents = Directory(
          p.join(layout.appToolRoot('flashskyai'), 'agents'),
        );
        await appAgents.create(recursive: true);
        await File(
          p.join(appAgents.path, 'README.md'),
        ).writeAsString('top-level');

        await layout.ensureSessionRuntimeInheritsWorkspace(
          'proj-a',
          'sess-1',
          'flashskyai',
        );

        final sessionAgents = p.join(
          layout.sessionRuntimeToolDir('proj-a', 'sess-1', 'flashskyai'),
          'agents',
        );
        expect(_inheritedPathExists(sessionAgents), isTrue);
        expect(
          await File(p.join(sessionAgents, 'README.md')).readAsString(),
          'top-level',
        );

        final sessionSkills = p.join(
          layout.sessionRuntimeToolDir('proj-a', 'sess-1', 'flashskyai'),
          'skills',
        );
        expect(
          Link(sessionSkills).existsSync(),
          isFalse,
          reason: 'session skills/ must not be an inherited symlink',
        );
      },
    );
  });
}

bool _inheritedPathExists(String path) {
  switch (FileSystemEntity.typeSync(path, followLinks: false)) {
    case FileSystemEntityType.link:
      return true;
    case FileSystemEntityType.directory:
      return Platform.isWindows;
    default:
      return false;
  }
}
