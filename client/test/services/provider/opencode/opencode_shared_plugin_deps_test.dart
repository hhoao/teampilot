import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/opencode/opencode_shared_plugin_deps.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  late Directory base;
  late RuntimeLayout layout;
  late LocalFilesystem fs;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('opencode_shared_deps_');
    fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
    await layout.ensureAppToolLayout('opencode');
  });

  tearDown(() async {
    await base.delete(recursive: true);
  });

  test('seed writes package.json and installs when plugin dir missing', () async {
    var installCalls = 0;
    final seeder = OpencodeSharedPluginDeps(
      layout: layout,
      fs: fs,
      resolvePluginVersion: () async => '1.18.4',
      npmInstall: (cwd) async {
        installCalls++;
        expect(cwd, layout.appToolRoot('opencode'));
        await Directory(
          p.join(cwd, 'node_modules', '@opencode-ai', 'plugin'),
        ).create(recursive: true);
        return 0;
      },
    );

    await seeder.ensureSharedInstalled();

    expect(installCalls, 1);
    final pkg = await File(
      p.join(layout.appToolRoot('opencode'), 'package.json'),
    ).readAsString();
    expect(pkg, contains('"@opencode-ai/plugin": "1.18.4"'));
    expect(
      await Directory(
        p.join(
          layout.appToolRoot('opencode'),
          'node_modules',
          '@opencode-ai',
          'plugin',
        ),
      ).exists(),
      isTrue,
    );
  });

  test('second ensure skips npm install when complete', () async {
    await Directory(
      p.join(
        layout.appToolRoot('opencode'),
        'node_modules',
        '@opencode-ai',
        'plugin',
      ),
    ).create(recursive: true);
    var installCalls = 0;
    final seeder = OpencodeSharedPluginDeps(
      layout: layout,
      fs: fs,
      resolvePluginVersion: () async => '1.18.4',
      npmInstall: (_) async {
        installCalls++;
        return 0;
      },
    );

    await seeder.ensureSharedInstalled();
    expect(installCalls, 0);
  });

  test('failed install removes incomplete node_modules', () async {
    final seeder = OpencodeSharedPluginDeps(
      layout: layout,
      fs: fs,
      resolvePluginVersion: () async => '1.18.4',
      npmInstall: (cwd) async {
        await Directory(p.join(cwd, 'node_modules', 'partial')).create(
          recursive: true,
        );
        return 1;
      },
    );

    await expectLater(seeder.ensureSharedInstalled(), throwsA(isA<Object>()));
    expect(
      await Directory(
        p.join(layout.appToolRoot('opencode'), 'node_modules'),
      ).exists(),
      isFalse,
    );
  });

  test('missing version fails without inventing a pin', () async {
    final seeder = OpencodeSharedPluginDeps(
      layout: layout,
      fs: fs,
      resolvePluginVersion: () async => null,
      npmInstall: (_) async => 0,
    );
    await expectLater(seeder.ensureSharedInstalled(), throwsA(isA<Object>()));
  });
}
