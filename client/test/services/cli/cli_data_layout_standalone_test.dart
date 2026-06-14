import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../../support/in_memory_filesystem.dart';

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

void main() {
  group('CliDataLayout standalone project paths', () {
    final layout = CliDataLayout(
      teampilotRoot: '/tp',
      fs: InMemoryFilesystem(),
    );

    test('standaloneProjectsDir is config-profiles/standalone/projects', () {
      expect(
        layout.standaloneProjectsDir(),
        '/tp/config-profiles/standalone/projects',
      );
    });

    test('standaloneProjectDir nests under standalone/projects/<projectId>', () {
      expect(
        layout.standaloneProjectDir('proj'),
        '/tp/config-profiles/standalone/projects/proj',
      );
    });

    test('standaloneProjectToolDir nests tool under project dir', () {
      expect(
        layout.standaloneProjectToolDir('proj', 'claude'),
        '/tp/config-profiles/standalone/projects/proj/claude',
      );
    });

    test('standaloneProjectSkillsDir uses flashskyai tool root', () {
      expect(
        layout.standaloneProjectSkillsDir('proj'),
        '/tp/config-profiles/standalone/projects/proj/flashskyai/skills',
      );
    });

    test('standaloneProjectPluginsDir uses flashskyai tool root', () {
      expect(
        layout.standaloneProjectPluginsDir('proj'),
        '/tp/config-profiles/standalone/projects/proj/flashskyai/plugins',
      );
    });

    test('standaloneProjectMcpDir is under project dir', () {
      expect(
        layout.standaloneProjectMcpDir('proj'),
        '/tp/config-profiles/standalone/projects/proj/mcp',
      );
    });

    test('standaloneProjectMcpServersFile is mcp/servers.json', () {
      expect(
        layout.standaloneProjectMcpServersFile('proj'),
        '/tp/config-profiles/standalone/projects/proj/mcp/servers.json',
      );
    });

    test('standaloneProjectSessionToolDir nests session and tool', () {
      expect(
        layout.standaloneProjectSessionToolDir('proj', 'sess', 'claude'),
        '/tp/config-profiles/standalone/projects/proj/sessions/sess/claude',
      );
    });

    test('trims projectId sessionId and tool like team helpers', () {
      expect(
        layout.standaloneProjectDir('  proj  '),
        layout.standaloneProjectDir('proj'),
      );
      expect(
        layout.standaloneProjectToolDir(' proj ', ' claude '),
        layout.standaloneProjectToolDir('proj', 'claude'),
      );
      expect(
        layout.standaloneProjectSessionToolDir(' proj ', ' sess ', ' claude '),
        layout.standaloneProjectSessionToolDir('proj', 'sess', 'claude'),
      );
    });

    test('uses filesystem path context from injected fs', () {
      final windowsLayout = CliDataLayout(
        teampilotRoot: r'C:\tp',
        fs: InMemoryFilesystem(
          pathContext: p.Context(style: p.Style.windows),
        ),
      );
      expect(
        windowsLayout.standaloneProjectSessionToolDir('proj', 'sess', 'claude'),
        r'C:\tp\config-profiles\standalone\projects\proj\sessions\sess\claude',
      );
    });
  });

  group('CliDataLayout standalone inherit', () {
    late Directory base;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('cli_layout_standalone_');
    });

    tearDown(() async {
      if (await base.exists()) {
        await base.delete(recursive: true);
      }
    });

    test(
      'ensureStandaloneProjectInheritsApp symlinks agents and skills from app',
      () async {
        final layout = CliDataLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('flashskyai');
        final appAgents = Directory(
          p.join(layout.appToolRoot('flashskyai'), 'agents'),
        );
        await appAgents.create(recursive: true);
        await File(p.join(appAgents.path, 'demo.md')).writeAsString('# demo');

        await layout.ensureStandaloneProjectInheritsApp('proj-a', 'flashskyai');

        final projectAgents = p.join(
          layout.standaloneProjectToolDir('proj-a', 'flashskyai'),
          'agents',
        );
        final projectSkills = p.join(
          layout.standaloneProjectToolDir('proj-a', 'flashskyai'),
          'skills',
        );
        expect(_inheritedPathExists(projectAgents), isTrue);
        expect(_inheritedPathExists(projectSkills), isTrue);
        if (Link(projectAgents).existsSync()) {
          expect(Link(projectAgents).targetSync(), appAgents.path);
        }
        expect(
          await File(p.join(projectAgents, 'demo.md')).readAsString(),
          '# demo',
        );
      },
    );

    test(
      'ensureStandaloneSessionInheritsProject chains app → project → session agents only',
      () async {
        final layout = CliDataLayout(
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

        await layout.ensureStandaloneSessionInheritsProject(
          'proj-a',
          'sess-1',
          'flashskyai',
        );

        // Agents are inherited via symlink.
        final sessionAgents = p.join(
          layout.standaloneProjectSessionToolDir('proj-a', 'sess-1', 'flashskyai'),
          'agents',
        );
        expect(_inheritedPathExists(sessionAgents), isTrue);
        expect(
          await File(p.join(sessionAgents, 'README.md')).readAsString(),
          'top-level',
        );

        // Skills are NOT inherited — they are provisioned separately.
        final sessionSkills = p.join(
          layout.standaloneProjectSessionToolDir('proj-a', 'sess-1', 'flashskyai'),
          'skills',
        );
        expect(_inheritedPathExists(sessionSkills), isFalse);
      },
    );

    test(
      'provisionStandaloneSessionSkillsFromProject copies project skills into session',
      () async {
        final layout = CliDataLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        // Set up project skills at standalone project path.
        final projectSkills = Directory(
          layout.standaloneProjectSkillsDir('proj-a'),
        );
        await projectSkills.create(recursive: true);
        final skillDir = Directory(p.join(projectSkills.path, 'my-skill'));
        await skillDir.create();
        await File(p.join(skillDir.path, 'instructions.md'))
            .writeAsString('# project skill');

        // Provision for claude.
        await layout.provisionStandaloneSessionSkillsFromProject(
          'proj-a',
          'sess-1',
          'claude',
        );

        final sessionSkills = p.join(
          layout.standaloneProjectSessionToolDir('proj-a', 'sess-1', 'claude'),
          'skills',
          'my-skill',
        );
        expect(Directory(sessionSkills).existsSync(), isTrue);
        expect(
          await File(p.join(sessionSkills, 'instructions.md')).readAsString(),
          '# project skill',
        );
      },
    );

    test(
      'ensureStandaloneProjectInheritsApp keeps populated project skills dir',
      () async {
        final layout = CliDataLayout(
          teampilotRoot: base.path,
          fs: LocalFilesystem(),
        );
        await layout.ensureAppToolLayout('flashskyai');
        final projectSkills = Directory(
          p.join(
            layout.standaloneProjectToolDir('proj-a', 'flashskyai'),
            'skills',
          ),
        );
        await projectSkills.create(recursive: true);
        await Directory(p.join(projectSkills.path, 'alpha')).create();

        await layout.ensureStandaloneProjectInheritsApp('proj-a', 'flashskyai');

        expect(Link(projectSkills.path).existsSync(), isFalse);
        expect(
          Directory(p.join(projectSkills.path, 'alpha')).existsSync(),
          isTrue,
        );
      },
    );
  });
}
