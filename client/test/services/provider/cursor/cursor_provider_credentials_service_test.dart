import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/claude_credential_link_result.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_provider_credentials_service.dart';

import '../../../support/in_memory_filesystem.dart';

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
      fs.pathContext.join(
        base,
        'providers',
        'cursor',
        'work',
        'home',
        '.config',
        'cursor',
        'auth.json',
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
  });

  test(
    'runAuthLogin with mock runner writes auth.json and returns ready',
    () async {
      final loginService = CursorProviderCredentialsService(
        fs: fs,
        basePath: base,
        processRunner: (executable, arguments, {environment}) async {
          expect(arguments, contains('login'));
          final home = environment?['HOME'];
          expect(home, isNotNull);
          await fs.writeString(
            layout.cliConfig(home!),
            jsonEncode({
              'authInfo': {'userId': 'u1', 'authId': 'a1'},
            }),
          );
          await fs.writeString(
            layout.authJson(home),
            jsonEncode({'accessToken': 'at1', 'refreshToken': 'rt1'}),
          );
          return ProcessResult(0, 0, '', '');
        },
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
        processRunner: (executable, arguments, {environment}) async {
          final home = environment?['HOME'];
          expect(home, isNotNull);
          await fs.writeString(layout.cliConfig(home!), loggedInCliConfig);
          return ProcessResult(0, 0, '', '');
        },
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
}
