import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/credential_action_result.dart';
import 'package:teampilot/models/credential_link_result.dart';
import 'package:teampilot/services/host/host_one_shot_runner.dart';
import 'package:teampilot/services/host/host_process_starter.dart';
import 'package:teampilot/services/host/process_run_handle.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_launch_environment.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_provider_credentials_service.dart';
import 'package:teampilot/services/provider/provider_credential_host_runner.dart';

import '../../../support/in_memory_filesystem.dart';

class _ExitZeroHandle implements ProcessRunHandle {
  @override
  Future<int> get exitCode => Future.value(0);

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  void kill() {}
}

class _AuthWritingStreamingStarter implements HostProcessStarter {
  _AuthWritingStreamingStarter({
    required this.fs,
    required this.layout,
    this.writeAuthJson = true,
    this.onStart,
  });

  final InMemoryFilesystem fs;
  final CursorHomeLayout layout;
  final bool writeAuthJson;
  final void Function(HostRunRequest request)? onStart;

  @override
  Future<ProcessRunHandle> start(HostRunRequest request) async {
    onStart?.call(request);
    final home = request.environment?['HOME'];
    expect(home, isNotNull);
    await fs.writeString(
      layout.cliConfig(home!),
      jsonEncode({
        'authInfo': {'userId': 'u1', 'authId': 'a1'},
      }),
    );
    if (writeAuthJson) {
      await fs.writeString(
        layout.authJson(home),
        jsonEncode({'accessToken': 'at1', 'refreshToken': 'rt1'}),
      );
    }
    return _ExitZeroHandle();
  }
}

ProviderCredentialHostRunner _loginHostRunner({
  required InMemoryFilesystem fs,
  required CursorHomeLayout layout,
  bool writeAuthJson = true,
  void Function(HostRunRequest request)? onStart,
}) {
  return ProviderCredentialHostRunner(
    oneShot: () => throw StateError('one-shot should not be called for login'),
    streaming: () => _AuthWritingStreamingStarter(
      fs: fs,
      layout: layout,
      writeAuthJson: writeAuthJson,
      onStart: onStart,
    ),
  );
}

void main() {
  late InMemoryFilesystem fs;
  late CursorProviderCredentialsService service;
  late CursorHomeLayout layout;
  const base = '/data/tp';

  const loggedInCliConfig = '''
{"authInfo":{"userId":"u1","authId":"a1"}}
''';

  const loggedInAuthJson = '''
{"accessToken":"at1","refreshToken":"rt1"}
''';

  Future<void> writeLoggedInProvider(String providerId) async {
    final home = fs.pathContext.join(
      base,
      'providers',
      'cursor',
      providerId,
      'home',
    );
    await fs.writeString(layout.cliConfig(home), loggedInCliConfig);
    await fs.writeString(layout.authJson(home), loggedInAuthJson);
  }

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CursorHomeLayout(pathContext: fs.pathContext);
    service = CursorProviderCredentialsService(fs: fs, basePath: base);
  });

  test('probe missing when no auth.json', () async {
    final probe = await service.probe('work');
    expect(probe.isReady, isFalse);
    expect(
      probe.credentialPath,
      layout.authJson(
        fs.pathContext.join(
          base,
          'providers',
          'cursor',
          'work',
          'home',
        ),
      ),
    );
  });

  test('probe missing when auth.json has no tokens', () async {
    final home = fs.pathContext.join(
      base,
      'providers',
      'cursor',
      'work',
      'home',
    );
    await fs.writeString(
      layout.authJson(home),
      '{"accessToken":"","refreshToken":""}',
    );
    final probe = await service.probe('work');
    expect(probe.isReady, isFalse);
  });

  test('probe ready when auth.json has tokens', () async {
    await writeLoggedInProvider('personal');
    final probe = await service.probe('personal');
    expect(probe.isReady, isTrue);
  });

  test('importFromGlobal copies cli-config.json and auth.json', () async {
    const home = '/home/user';
    await fs.writeString(layout.cliConfig(home), loggedInCliConfig);
    await fs.writeString(layout.authJson(home), loggedInAuthJson);
    final result = await service.importFromGlobal('work', homeDirectory: home);
    expect(result.ok, isTrue);
    expect((await service.probe('work')).isReady, isTrue);
    final providerHome = fs.pathContext.join(
      base,
      'providers',
      'cursor',
      'work',
      'home',
    );
    final cliBytes = await fs.readBytes(layout.cliConfig(providerHome));
    expect(cliBytes, isNotNull);
    expect(utf8.decode(cliBytes!), contains('u1'));
    final authBytes = await fs.readBytes(layout.authJson(providerHome));
    expect(authBytes, isNotNull);
    expect(utf8.decode(authBytes!), contains('at1'));
  });

  test(
    'importFromGlobal seeds default cli-config when source file is missing',
    () async {
      const home = '/home/user';
      await fs.writeString(layout.authJson(home), loggedInAuthJson);
      final result = await service.importFromGlobal(
        'work',
        homeDirectory: home,
      );
      expect(result.ok, isTrue);
      expect((await service.probe('work')).isReady, isTrue);
      final providerHome = fs.pathContext.join(
        base,
        'providers',
        'cursor',
        'work',
        'home',
      );
      final cliBytes = await fs.readBytes(layout.cliConfig(providerHome));
      expect(cliBytes, isNotNull);
      expect(utf8.decode(cliBytes!), contains('"version":1'));
    },
  );

  test(
    'importFromGlobal reports missing auth.json before cli-config.json',
    () async {
      const home = '/home/user';
      final result = await service.importFromGlobal(
        'work',
        homeDirectory: home,
      );
      expect(result.ok, isFalse);
      expect(result.failure?.code, CredentialActionFailureCode.requiredFileMissing);
      expect(
        result.failure?.path,
        anyOf(
          layout.authJson(home),
          layout.globalAuthJsonCandidates(home).first,
        ),
      );
    },
  );

  test('importFromGlobal finds auth.json under Windows APPDATA', () async {
    final winContext = p.Context(style: p.Style.windows);
    final winFs = InMemoryFilesystem(pathContext: winContext);
    final winLayout = CursorHomeLayout(pathContext: winContext);
    final winService = CursorProviderCredentialsService(
      fs: winFs,
      basePath: base,
    );
    const home = r'C:\Users\haung';
    const appData = r'C:\Users\haung\AppData\Roaming';
    final appDataAuth = winContext.join(appData, 'Cursor', 'auth.json');
    await winFs.writeString(winLayout.cliConfig(home), loggedInCliConfig);
    await winFs.writeString(appDataAuth, loggedInAuthJson);
    final result = await winService.importFromGlobal(
      'work',
      homeDirectory: home,
      platformEnv: const {'APPDATA': appData},
    );
    expect(result.ok, isTrue);
    expect((await winService.probe('work')).isReady, isTrue);
  });

  test('importAuthJsonFile copies auth.json only', () async {
    const source = '/tmp/auth.json';
    await fs.writeString(source, loggedInAuthJson);
    final result = await service.importAuthJsonFile('work', source);
    expect(result.ok, isTrue);
    expect((await service.probe('work')).isReady, isTrue);
  });

  test('syncAuthToMemberHome links cli-config and copies auth.json', () async {
    final providerHomePath = fs.pathContext.join(
      base,
      'providers',
      'cursor',
      'work',
      'home',
    );
    await writeLoggedInProvider('work');

    const memberHome = '/data/tp/identities-runtime/t1/members/s1/cursor/home';
    final result = await service.syncAuthToMemberHome('work', memberHome);
    expect(result, CredentialLinkResult.linked);
    expect(
      fs.symlinks[layout.cliConfig(memberHome)],
      layout.cliConfig(providerHomePath),
    );
    expect((await fs.stat(layout.authJson(memberHome))).isFile, isTrue);
    expect(fs.symlinks[layout.authJson(memberHome)], isNull);
    final authBytes = await fs.readBytes(layout.authJson(memberHome));
    expect(utf8.decode(authBytes!), contains('at1'));
  });

  test(
    'syncAuthToMemberHome replaces auth when switching providers',
    () async {
      await writeLoggedInProvider('acct-a');
      final bHome = fs.pathContext.join(
        base,
        'providers',
        'cursor',
        'acct-b',
        'home',
      );
      await fs.writeString(
        layout.cliConfig(bHome),
        '{"authInfo":{"userId":"u-b","authId":"a-b"}}',
      );
      await fs.writeString(
        layout.authJson(bHome),
        '{"accessToken":"at-b","refreshToken":"rt-b"}',
      );

      const memberHome = '/data/tp/identities-runtime/t1/members/s1/cursor/home';
      await service.syncAuthToMemberHome('acct-a', memberHome);
      final result = await service.syncAuthToMemberHome('acct-b', memberHome);

      expect(result, isNot(CredentialLinkResult.alreadyPresent));
      final authBytes = await fs.readBytes(layout.authJson(memberHome));
      expect(utf8.decode(authBytes!), contains('at-b'));
      expect(
        fs.symlinks[layout.cliConfig(memberHome)],
        layout.cliConfig(bHome),
      );
    },
  );

  test(
    'syncAuthToMemberHome merges new authInfo into overlaid cli-config',
    () async {
      await writeLoggedInProvider('acct-a');
      final bHome = fs.pathContext.join(
        base,
        'providers',
        'cursor',
        'acct-b',
        'home',
      );
      await fs.writeString(
        layout.cliConfig(bHome),
        '{"authInfo":{"userId":"u-b","authId":"a-b"}}',
      );
      await fs.writeString(
        layout.authJson(bHome),
        '{"accessToken":"at-b","refreshToken":"rt-b"}',
      );

      const memberHome = '/data/tp/identities-runtime/t1/members/s1/cursor/home';
      await service.syncAuthToMemberHome('acct-a', memberHome);
      await fs.removeRecursive(layout.cliConfig(memberHome));
      await fs.writeString(
        layout.cliConfig(memberHome),
        jsonEncode({
          'authInfo': {'userId': 'u1', 'authId': 'a1'},
          'permissions': {
            'allow': ['Mcp(teampilot-bus)'],
          },
          'model': 'keep-me',
        }),
      );

      await service.syncAuthToMemberHome('acct-b', memberHome);

      final authBytes = await fs.readBytes(layout.authJson(memberHome));
      expect(utf8.decode(authBytes!), contains('at-b'));
      final decoded =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      expect((decoded['authInfo'] as Map)['userId'], 'u-b');
      expect(decoded['model'], 'keep-me');
      expect((decoded['permissions'] as Map)['allow'], ['Mcp(teampilot-bus)']);
    },
  );

  test(
    'syncAuthToMemberHome is alreadyPresent when same provider is already linked',
    () async {
      await writeLoggedInProvider('work');
      const memberHome = '/data/tp/identities-runtime/t1/members/s1/cursor/home';
      await service.syncAuthToMemberHome('work', memberHome);
      final second = await service.syncAuthToMemberHome('work', memberHome);
      expect(second, CredentialLinkResult.alreadyPresent);
    },
  );

  test('loginEnvironment sets HOME to provider home', () {
    final env = service.loginEnvironment('work');
    expect(
      env['HOME'],
      fs.pathContext.join(base, 'providers', 'cursor', 'work', 'home'),
    );
    expect(
      env['USERPROFILE'],
      fs.pathContext.join(base, 'providers', 'cursor', 'work', 'home'),
    );
    expect(
      env[CursorLaunchEnvironment.credentialStoreEnvKey],
      CursorLaunchEnvironment.credentialStoreFile,
    );
  });

  test('runAuthLogin sets NO_OPEN_BROWSER for headless SSH login', () async {
    HostRunRequest? captured;
    final loginService = CursorProviderCredentialsService(
      fs: fs,
      basePath: base,
      hostRunner: _loginHostRunner(
        fs: fs,
        layout: layout,
        onStart: (request) => captured = request,
      ),
    );

    await loginService.runAuthLogin('work');
    expect(captured?.environment?['NO_OPEN_BROWSER'], '1');
  });

  test(
    'runAuthLogin with mock runner writes auth.json and returns ready',
    () async {
      final loginService = CursorProviderCredentialsService(
        fs: fs,
        basePath: base,
        hostRunner: _loginHostRunner(
          fs: fs,
          layout: layout,
          onStart: (request) {
            expect(request.arguments, contains('login'));
          },
        ),
      );

      final loginResult = await loginService.runAuthLogin('work');
      expect(loginResult.ok, isTrue);
      expect((await loginService.probe('work')).isReady, isTrue);
    },
  );

  test(
    'runAuthLogin clears partial artifacts when verification fails',
    () async {
      final loginService = CursorProviderCredentialsService(
        fs: fs,
        basePath: base,
        hostRunner: _loginHostRunner(
          fs: fs,
          layout: layout,
          writeAuthJson: false,
        ),
      );

      final loginResult = await loginService.runAuthLogin('work');
      expect(loginResult.ok, isFalse);
      final providerHome = fs.pathContext.join(
        base,
        'providers',
        'cursor',
        'work',
        'home',
      );
      expect((await fs.stat(layout.cliConfig(providerHome))).isFile, isFalse);
      expect((await fs.stat(layout.authJson(providerHome))).isFile, isFalse);
    },
  );

  test('importFromGlobal replace overwrites existing artifacts', () async {
    const home = '/home/user';
    final providerHome = fs.pathContext.join(
      base,
      'providers',
      'cursor',
      'work',
      'home',
    );
    await fs.writeString(
      layout.cliConfig(providerHome),
      '{"authInfo":{"userId":"stale"}}',
    );
    await fs.writeString(
      layout.authJson(providerHome),
      '{"accessToken":"old"}',
    );
    await fs.writeString(layout.cliConfig(home), loggedInCliConfig);
    await fs.writeString(layout.authJson(home), loggedInAuthJson);

    final result = await service.importFromGlobal(
      'work',
      homeDirectory: home,
      replace: true,
    );

    expect(result.ok, isTrue);
    expect((await service.probe('work')).isReady, isTrue);
    final authBytes = await fs.readBytes(layout.authJson(providerHome));
    expect(utf8.decode(authBytes!), contains('at1'));
  });

  test('revokeCredentials clears stale artifacts when not ready', () async {
    final providerHome = fs.pathContext.join(
      base,
      'providers',
      'cursor',
      'work',
      'home',
    );
    await fs.writeString(layout.cliConfig(providerHome), loggedInCliConfig);

    final result = await service.revokeCredentials('work');

    expect(result.ok, isTrue);
    expect((await fs.stat(layout.cliConfig(providerHome))).isFile, isFalse);
    expect((await service.probe('work')).isReady, isFalse);
  });

  test('revokeCredentials runs logout via host runner when ready', () async {
    await writeLoggedInProvider('work');
    HostRunRequest? logoutRequest;
    final revokeService = CursorProviderCredentialsService(
      fs: fs,
      basePath: base,
      hostRunner: ProviderCredentialHostRunner(
        oneShot: () => _LogoutCapturingOneShot((request) {
          logoutRequest = request;
        }),
        streaming: () => throw StateError('streaming should not be called'),
      ),
    );

    final result = await revokeService.revokeCredentials('work');

    expect(result.ok, isTrue);
    expect(logoutRequest, isNotNull);
    expect(logoutRequest!.arguments, contains('logout'));
    expect((await revokeService.probe('work')).isReady, isFalse);
  });
}

class _LogoutCapturingOneShot implements HostOneShotRunner {
  _LogoutCapturingOneShot(this.onRun);

  final void Function(HostRunRequest request) onRun;

  @override
  Future<HostRunResult> run(HostRunRequest request) async {
    onRun(request);
    return const HostRunResult(exitCode: 0, stdout: '', stderr: '');
  }
}
