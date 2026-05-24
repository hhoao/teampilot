import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli_data_layout.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../support/in_memory_filesystem.dart';

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
  group('CliDataLayout path computation', () {
    final layout = CliDataLayout(
      teampilotRoot: '/tp',
      fs: InMemoryFilesystem(),
    );

    test('appToolRoot is config-profiles/<tool>', () {
      expect(
        layout.appToolRoot('flashskyai'),
        '/tp/config-profiles/flashskyai',
      );
      expect(layout.appToolRoot('claude'), '/tp/config-profiles/claude');
    });

    test('teamToolDir is config-profiles/teams/<id>/<tool>', () {
      expect(
        layout.teamToolDir('team-a', 'flashskyai'),
        '/tp/config-profiles/teams/team-a/flashskyai',
      );
    });

    test('memberToolDir nests under members/<sessionId>/<tool>', () {
      expect(
        layout.memberToolDir('team-a', 'sess-1', 'flashskyai'),
        '/tp/config-profiles/teams/team-a/members/sess-1/flashskyai',
      );
    });

    test('transcriptSearchRoots returns app + team + member for each tool', () {
      final roots = layout.transcriptSearchRoots(
        teamId: 'team-a',
        runtimeSessionId: 'sess-1',
      );
      expect(roots, [
        '/tp/config-profiles/claude',
        '/tp/config-profiles/flashskyai',
        '/tp/config-profiles/codex',
        '/tp/config-profiles/teams/team-a/claude',
        '/tp/config-profiles/teams/team-a/flashskyai',
        '/tp/config-profiles/teams/team-a/codex',
        '/tp/config-profiles/teams/team-a/members/sess-1/claude',
        '/tp/config-profiles/teams/team-a/members/sess-1/flashskyai',
        '/tp/config-profiles/teams/team-a/members/sess-1/codex',
      ]);
    });

    test('transcriptSearchRoots omits member layer when sessionId empty', () {
      final roots = layout.transcriptSearchRoots(
        teamId: 'team-a',
        runtimeSessionId: '',
        tools: const ['flashskyai'],
      );
      expect(roots, [
        '/tp/config-profiles/flashskyai',
        '/tp/config-profiles/teams/team-a/flashskyai',
      ]);
    });

    test('appFlashskyaiLlmConfigFile points at <root>/llm_config.json', () {
      expect(
        layout.appFlashskyaiLlmConfigFile,
        '/tp/config-profiles/flashskyai/llm_config.json',
      );
    });
  });

  group('projectBucketForPrimaryPath', () {
    test('POSIX paths slugify directly', () {
      expect(
        CliDataLayout.projectBucketForPrimaryPath('/home/hhoa/agent'),
        '-home-hhoa-agent',
      );
    });

    test('Windows drive paths map to /mnt/<drive>/...', () {
      expect(
        CliDataLayout.projectBucketForPrimaryPath(
          r'D:\a\teampilot\teampilot\client',
        ),
        '-mnt-d-a-teampilot-teampilot-client',
      );
      expect(
        CliDataLayout.projectBucketForPrimaryPath(r'C:\Users\hhoa\agent'),
        '-mnt-c-Users-hhoa-agent',
      );
    });

    test('empty path returns empty bucket', () {
      expect(CliDataLayout.projectBucketForPrimaryPath(''), '');
    });
  });

  group('CliDataLayout.ensure*', () {
    late Directory base;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('cli_layout_');
    });

    tearDown(() async {
      if (await base.exists()) {
        await base.delete(recursive: true);
      }
    });

    test('ensureAppToolLayout creates app tool dir', () async {
      final layout = CliDataLayout(
        teampilotRoot: base.path,
        fs: LocalFilesystem(),
      );
      await layout.ensureAppToolLayout('flashskyai');
      expect(
        await Directory(layout.appToolRoot('flashskyai')).exists(),
        isTrue,
      );
    });

    test(
      'ensureTeamInheritsApp symlinks agents and skills from app level',
      () async {
        final layout = CliDataLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('flashskyai');
        // Seed an app-level file so we can verify inheritance via readlink.
        final appAgents = Directory(
          p.join(layout.appToolRoot('flashskyai'), 'agents'),
        );
        await appAgents.create(recursive: true);
        await File(p.join(appAgents.path, 'demo.md')).writeAsString('# demo');

        await layout.ensureTeamInheritsApp('team-a', 'flashskyai');

        final teamAgents = p.join(
          layout.teamToolDir('team-a', 'flashskyai'),
          'agents',
        );
        final teamSkills = p.join(
          layout.teamToolDir('team-a', 'flashskyai'),
          'skills',
        );
        expect(Link(teamAgents).existsSync(), isTrue);
        expect(Link(teamSkills).existsSync(), isTrue);
        expect(Link(teamAgents).targetSync(), appAgents.path);

        // Reading through the symlink yields the app-level content.
        expect(
          await File(p.join(teamAgents, 'demo.md')).readAsString(),
          '# demo',
        );
      },
    );

    test(
      'ensureMemberInheritsTeam chains app → team → member symlinks',
      () async {
        final layout = CliDataLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('flashskyai');
        final appSkills = Directory(
          p.join(layout.appToolRoot('flashskyai'), 'skills'),
        );
        await appSkills.create(recursive: true);
        await File(
          p.join(appSkills.path, 'README.md'),
        ).writeAsString('top-level');

        await layout.ensureMemberInheritsTeam('team-a', 'sess-1', 'flashskyai');

        final memberSkills = _posixPath.join(
          layout.memberToolDir('team-a', 'sess-1', 'flashskyai'),
          'skills',
        );
        expect(Link(memberSkills).existsSync(), isTrue);
        // Member -> team -> app: reading through both yields original file.
        expect(
          await File(p.join(memberSkills, 'README.md')).readAsString(),
          'top-level',
        );
      },
    );

    test(
      'provisionMemberPluginsFromTeam copies team bundles into member CONFIG_DIR',
      () async {
        final layout = CliDataLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        final teamPlugins = Directory(
          p.join(layout.teamPluginsDir('team-a')),
        )..createSync(recursive: true);
        final pluginRoot = Directory(p.join(teamPlugins.path, 'demo-plugin'))
          ..createSync();
        Directory(p.join(pluginRoot.path, '.claude-plugin')).createSync();
        await File(
          p.join(pluginRoot.path, '.claude-plugin', 'plugin.json'),
        ).writeAsString('{"name":"demo-plugin","version":"1.0.0"}');
        await File(p.join(pluginRoot.path, '.mcp.json')).writeAsString('{}');

        await layout.provisionMemberPluginsFromTeam(
          'team-a',
          'sess-1',
          'flashskyai',
        );
        // flashskyai session mirrors marketplace manifest for FlashskyAI CLI
        final memberPlugins = p.join(
          layout.memberToolDir('team-a', 'sess-1', 'flashskyai'),
          'plugins',
        );
        expect(Link(memberPlugins).existsSync(), isFalse);
        final copied = Directory(p.join(memberPlugins, 'demo-plugin'));
        expect(copied.existsSync(), isTrue);
        expect(
          File(
            p.join(copied.path, '.claude-plugin', 'plugin.json'),
          ).existsSync(),
          isTrue,
        );
        expect(File(p.join(copied.path, '.mcp.json')).existsSync(), isTrue);
        expect(
          File(p.join(copied.path, '.flashskyai-plugin', 'plugin.json'))
              .existsSync(),
          isTrue,
        );

        await layout.provisionMemberPluginsFromTeam(
          'team-a',
          'sess-2',
          'claude',
        );
        final claudeCopied = Directory(
          p.join(
            layout.memberToolDir('team-a', 'sess-2', 'claude'),
            'plugins',
            'demo-plugin',
          ),
        );
        expect(claudeCopied.existsSync(), isTrue);
        expect(
          File(
            p.join(claudeCopied.path, '.claude-plugin', 'plugin.json'),
          ).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(claudeCopied.path, '.flashskyai-plugin', 'plugin.json'))
              .existsSync(),
          isFalse,
        );
      },
    );

    test('symlink failure falls back to copy', () async {
      final fs = _NoSymlinkFilesystem();
      final layout = CliDataLayout(teampilotRoot: '/tp', fs: fs);
      await layout.ensureAppToolLayout('flashskyai');
      final appAgents = _posixPath.join(
        layout.appToolRoot('flashskyai'),
        'agents',
      );
      await fs.ensureDir(appAgents);
      await fs.writeString(_posixPath.join(appAgents, 'demo.md'), 'hello');

      await layout.ensureTeamInheritsApp('team-a', 'flashskyai');

      final teamAgentsPath = _posixPath.join(
        layout.teamToolDir('team-a', 'flashskyai'),
        'agents',
      );
      expect(fs.symlinks.containsKey(teamAgentsPath), isFalse);
      expect(fs.directories.contains(teamAgentsPath), isTrue);
      // Copy preserved the demo.md.
      expect(
        await fs.readString(_posixPath.join(teamAgentsPath, 'demo.md')),
        'hello',
      );
    });
  });
}
