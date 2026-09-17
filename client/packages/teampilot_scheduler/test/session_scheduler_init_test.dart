import 'package:path/path.dart' as p;
import 'package:teampilot_fs/teampilot_fs.dart';
import 'package:teampilot_scheduler/teampilot_scheduler.dart';
import 'package:test/test.dart';

class _WritePlugin implements SessionCliPlugin {
  @override
  String get toolId => 'cursor';

  @override
  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required Filesystem workFs,
    required LaunchManifest manifest,
  }) async {
    manifest.writeFile('${request.workRoot}/hello.txt', 'hi');
  }

  @override
  String sessionConfigDir(SessionLayout layout, SessionInitRequest request) =>
      layout.sessionRuntimeToolDir(
        request.workspaceId,
        request.sessionId,
        request.cli,
        memberId: request.memberId,
      );

  @override
  Future<void> afterApply({
    required Filesystem workFs,
    required SessionLayout layout,
    required Map<String, String> environment,
  }) async {}

  @override
  SessionSpawnSpec buildSpawn({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Map<String, String> environment,
  }) {
    return SessionSpawnSpec(
      executable: request.cliExecutablePath,
      argv: const ['--version'],
      env: environment,
      cwd: request.workingDirectory,
    );
  }
}

class _WriteResource implements ResourceContributor {
  @override
  String get id => 'write-resource';

  @override
  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required LaunchManifest manifest,
  }) async {
    manifest.writeFile(
      '${request.workRoot}/from-resource.txt',
      'from-resource',
    );
  }
}

void main() {
  final posix = p.Context(style: p.Style.posix);

  SessionInitRequest req({String cli = 'cursor'}) => SessionInitRequest(
    workspaceId: 'w',
    sessionId: 's',
    memberId: 's',
    cli: cli,
    cliExecutablePath: '/bin/cursor-agent',
    homeRoot: '/home-tp',
    workRoot: '/work-tp',
    workingDirectory: '/proj',
  );

  test('init applies plugin writes and returns spawn spec', () async {
    final home = InMemoryFilesystem(pathContext: posix);
    final work = InMemoryFilesystem(pathContext: posix);
    await work.ensureDir('/work-tp');
    final result = await const SessionScheduler().init(
      request: req(),
      homeFs: home,
      workFs: work,
      plugin: _WritePlugin(),
    );
    expect(await work.readString('/work-tp/hello.txt'), 'hi');
    expect(result.spawn.executable, '/bin/cursor-agent');
    expect(result.spawn.argv, ['--version']);
    expect(result.spawn.cwd, '/proj');
  });

  test('init applies resource contributor writes', () async {
    final home = InMemoryFilesystem(pathContext: posix);
    final work = InMemoryFilesystem(pathContext: posix);
    await work.ensureDir('/work-tp');
    await const SessionScheduler().init(
      request: req(),
      homeFs: home,
      workFs: work,
      plugin: _WritePlugin(),
      resources: [_WriteResource()],
    );
    expect(
      await work.readString('/work-tp/from-resource.txt'),
      'from-resource',
    );
    expect(await work.readString('/work-tp/hello.txt'), 'hi');
  });

  test(
    'off-home init copies home identity file onto workFs without a script runner',
    () async {
      final home = InMemoryFilesystem(pathContext: posix);
      final work = InMemoryFilesystem(pathContext: posix);
      await home.writeString(
        '/home-tp/identities-runtime/x/cursor/a.json',
        '{"k":1}',
      );
      await work.ensureDir('/work-tp');
      await const SessionScheduler().init(
        request: req(),
        homeFs: home,
        workFs: work,
        plugin: _CopyIdentityPlugin(),
      );
      expect(
        await work.readString('/work-tp/identities-runtime/x/cursor/a.json'),
        '{"k":1}',
      );
    },
  );

  test(
    'unprojectable missing source becomes SessionInitException project',
    () async {
      final home = InMemoryFilesystem(pathContext: posix);
      final work = InMemoryFilesystem(pathContext: posix);
      await work.ensureDir('/work-tp');

      try {
        await const SessionScheduler().init(
          request: req(),
          homeFs: home,
          workFs: work,
          plugin: _BadLinkPlugin(),
        );
        fail('expected SessionInitException');
      } on SessionInitException catch (e) {
        expect(e.stage, SessionInitStage.project);
      }
    },
  );

  test('plugin tool mismatch becomes SessionInitException layout', () async {
    final home = InMemoryFilesystem(pathContext: posix);
    final work = InMemoryFilesystem(pathContext: posix);
    await work.ensureDir('/work-tp');

    try {
      await const SessionScheduler().init(
        request: req(cli: 'codex'),
        homeFs: home,
        workFs: work,
        plugin: _WritePlugin(),
      );
      fail('expected SessionInitException');
    } on SessionInitException catch (e) {
      expect(e.stage, SessionInitStage.layout);
      expect(e.message, 'plugin/tool mismatch');
    }
  });
}

class _CopyIdentityPlugin extends _WritePlugin {
  @override
  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required Filesystem workFs,
    required LaunchManifest manifest,
  }) async {
    manifest.copyFile(
      source: '/home-tp/identities-runtime/x/cursor/a.json',
      destination: '/work-tp/identities-runtime/x/cursor/a.json',
    );
  }
}

class _BadLinkPlugin extends _WritePlugin {
  @override
  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required Filesystem workFs,
    required LaunchManifest manifest,
  }) async {
    manifest.symlink(
      linkPath: '${request.workRoot}/l',
      target: '/not/in/roots',
    );
  }
}
