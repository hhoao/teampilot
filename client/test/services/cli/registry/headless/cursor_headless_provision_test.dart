import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cursor/capabilities/headless.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  const cap = CursorHeadlessCapability();
  const loggedInAuthJson = '{"accessToken":"at1","refreshToken":"rt1"}';

  late CursorHomeLayout layout;
  late String configDir;

  setUp(() {
    layout = CursorHomeLayout(pathContext: AppStorage.fs.pathContext);
    configDir = p.join(AppStorage.home, 'headless-home');
  });

  HeadlessProvisionContext ctx({
    String providerId = 'work',
    AppProviderConfig? provider,
  }) => HeadlessProvisionContext(
    provider: provider,
    providerId: providerId,
    model: '',
    effort: '',
    configDir: configDir,
  );

  /// Seeds a logged-in official provider store under AppStorage.
  Future<void> seedProviderStore(String providerId) async {
    final fs = AppStorage.fs;
    final serviceHome = p.join(
      AppStorage.paths.basePath,
      'providers',
      'cursor',
      providerId,
      'home',
    );
    await fs.writeString(
      layout.cliConfig(serviceHome),
      '{"authInfo":{"userId":"u1","authId":"a1"}}',
    );
    await fs.ensureDir(layout.authDir(serviceHome));
    await fs.writeString(layout.authJson(serviceHome), loggedInAuthJson);
  }

  test(
    'provision materializes provider credentials into the isolated home',
    () async {
      await seedProviderStore('work');
      const provider = AppProviderConfig(
        id: 'work',
        cli: CliTool.cursor,
        name: 'Work',
        isOfficial: true,
      );

      final result = await cap.provision(ctx(provider: provider));

      expect(result.credentialsReady, isTrue);
      expect(result.warnings, isEmpty);
      // Auth landed at the platform anchor inside the temp home, and the
      // cli-config came along for the ride (cursor-agent needs both).
      expect(
        await AppStorage.fs.readString(layout.authJson(configDir)),
        loggedInAuthJson,
      );
      expect(
        (await AppStorage.fs.stat(layout.cliConfig(configDir))).isFile,
        isTrue,
      );
    },
  );

  test(
    'provision reports not-ready when official provider has no credentials',
    () async {
      const provider = AppProviderConfig(
        id: 'work',
        cli: CliTool.cursor,
        name: 'Work',
        isOfficial: true,
      );

      final result = await cap.provision(ctx(provider: provider));

      expect(result.credentialsReady, isFalse);
      expect(result.warnings, contains('cursor_credentials_missing'));
    },
  );

  test(
    'provision is ready for non-official providers without credentials',
    () async {
      const provider = AppProviderConfig(
        id: 'custom',
        cli: CliTool.cursor,
        name: 'Custom',
      );

      final result = await cap.provision(
        ctx(provider: provider, providerId: 'custom'),
      );

      expect(result.credentialsReady, isTrue);
    },
  );

  test(
    'provision falls back to the global login under the storage home',
    () async {
      final fs = AppStorage.fs;
      await fs.ensureDir(layout.authDir(AppStorage.home));
      await fs.writeString(layout.authJson(AppStorage.home), loggedInAuthJson);

      final result = await cap.provision(ctx(providerId: ''));

      expect(result.credentialsReady, isTrue);
      final auth = await fs.readString(layout.authJson(configDir));
      expect(jsonDecode(auth!)['accessToken'], 'at1');
    },
  );

  test('provision is not ready without provider or global login', () async {
    final result = await cap.provision(ctx(providerId: ''));

    expect(result.credentialsReady, isFalse);
    expect(result.warnings, contains('cursor_credentials_missing'));
  });

  test('buildEnvironment pins every anchor inside the temp home', () {
    final env = cap.buildEnvironment(
      HeadlessLaunchContext(
        prompt: 'P',
        model: '',
        effort: '',
        configDir: '/tmp/headless-home',
      ),
    );
    expect(env['HOME'], '/tmp/headless-home');
    expect(env['USERPROFILE'], '/tmp/headless-home');
    expect(
      env['CURSOR_CONFIG_DIR'],
      p.join('/tmp/headless-home', CursorHomeLayout.cursorDirName),
    );
    // POSIX-style temp dir → XDG branch on any host (deterministic).
    expect(env['XDG_CONFIG_HOME'], '/tmp/headless-home/.config');
    expect(env.containsKey('APPDATA'), isFalse);
  });
}
