import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/launch/launch_manifest.dart';
import 'package:teampilot/services/launch/manifest_executor.dart';
import 'package:teampilot/services/launch/manifest_filesystem.dart';
import 'package:teampilot/services/provider/cursor/cursor_member_home_passthrough.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  group('ManifestFilesystem', () {
    test('removeRecursive stages op without mutating readDelegate', () async {
      final home = InMemoryFilesystem();
      const path =
          '/teampilot/workspace/ws/sessions/s1/runtime/claude/creds.json';
      home.files[path] = 'home-secret';

      final manifest = LaunchManifest();
      final staging = ManifestFilesystem(
        manifest: manifest,
        readDelegate: home,
      );

      await staging.removeRecursive(path);

      expect(home.files[path], 'home-secret');
      expect(
        manifest.entries.whereType<ManifestRemoveRecursive>().map(
          (e) => e.path,
        ),
        [path],
      );
    });

    test(
      'rename from readDelegate copies into manifest without mutating home',
      () async {
        final home = InMemoryFilesystem();
        const from = '/teampilot/from.json';
        const to = '/teampilot/to.json';
        home.files[from] = '{"ok":true}';

        final manifest = LaunchManifest();
        final staging = ManifestFilesystem(
          manifest: manifest,
          readDelegate: home,
        );

        await staging.rename(from, to);

        expect(home.files.containsKey(from), isTrue);
        expect(home.files.containsKey(to), isFalse);
        expect(manifest.files[to], '{"ok":true}');
        expect(manifest.entries.whereType<ManifestRemoveRecursive>().length, 1);
      },
    );

    test(
      'listDir still sees real home after ensureDir under that home',
      () async {
        final disk = InMemoryFilesystem();
        const realHome = '/home/user';
        const pubCache = '$realHome/.pub-cache';
        const memberHome =
            '$realHome/.local/share/com.hhoa.teampilot/workspace/'
            'ws/sessions/s1/runtime/cursor/home';
        await disk.ensureDir(pubCache);
        await disk.ensureDir(realHome);

        final staging = ManifestFilesystem(
          manifest: LaunchManifest(),
          readDelegate: disk,
        );
        await staging.ensureDir(memberHome);

        final names = (await staging.listDir(realHome)).map((e) => e.name);
        expect(names, contains('.pub-cache'));
      },
    );

    test(
      'listDir stays empty for brand-new overlay-only dirs',
      () async {
        final disk = InMemoryFilesystem();
        const fresh = '/teampilot/workspace/ws/sessions/s1/runtime/cursor/home';

        final staging = ManifestFilesystem(
          manifest: LaunchManifest(),
          readDelegate: disk,
        );
        await staging.ensureDir(fresh);

        expect(await staging.listDir(fresh), isEmpty);
      },
    );

    test(
      'cursor home passthrough stages symlinks after ensureDir under real home',
      () async {
        final disk = InMemoryFilesystem();
        const realHome = '/home/user';
        const pubCache = '$realHome/.pub-cache';
        const memberHome =
            '$realHome/.local/share/com.hhoa.teampilot/workspace/'
            'ws/sessions/s1/runtime/cursor/home';
        await disk.ensureDir(pubCache);

        final manifest = LaunchManifest();
        final staging = ManifestFilesystem(
          manifest: manifest,
          readDelegate: disk,
        );
        await CursorMemberHomePassthrough(fs: staging).mirror(
          realHomeRoot: realHome,
          memberHomeRoot: memberHome,
        );

        expect(
          manifest.entries.whereType<ManifestSymlink>().map((e) => e.linkPath),
          contains('$memberHome/.pub-cache'),
        );

        await const ManifestExecutor().flush(
          manifest: manifest,
          targetFs: disk,
          sourceFs: disk,
        );
        expect(
          await disk.readSymlinkTarget('$memberHome/.pub-cache'),
          pubCache,
        );
      },
    );
  });

  group('LaunchManifest', () {
    test('ensureDir dedupes repeated paths', () {
      final manifest = LaunchManifest()
        ..ensureDir('/a')
        ..ensureDir('/a/b')
        ..ensureDir('/a')
        ..ensureDir('/a/b');

      expect(
        manifest.entries.whereType<ManifestEnsureDir>().map((e) => e.path),
        ['/a', '/a/b'],
      );
    });
  });

  group('ManifestExecutor', () {
    test(
      'flush throws when copy source is missing across filesystems',
      () async {
        final source = InMemoryFilesystem();
        final target = InMemoryFilesystem();
        final manifest = LaunchManifest()
          ..copyFile(source: '/missing', destination: '/dest/file.txt');

        await expectLater(
          const ManifestExecutor().flush(
            manifest: manifest,
            targetFs: target,
            sourceFs: source,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('/missing'),
            ),
          ),
        );
      },
    );

    test('ssh script heredoc delimiter avoids content collision', () {
      const content = 'data __TP_MANIFEST_42__ tail';
      final manifest = LaunchManifest()..writeFile('/tmp/out', content);
      final script = ManifestExecutor.debugBuildApplyScript(manifest);
      expect(script, contains(content));
      expect(script.split("<<'").length, greaterThan(1));
    });

    test('ssh same-host script keeps remote copyTree and symlink ops', () {
      final manifest = LaunchManifest()
        ..ensureDir('/session/home')
        ..symlink(linkPath: '/session/home/.cache', target: '/root/.cache')
        ..copyTree(source: '/cli-defaults/cursor', destination: '/session/cursor')
        ..copyFile(
          source: '/cli-defaults/cursor/settings.json',
          destination: '/session/cursor/settings.json',
        );

      final script = ManifestExecutor.debugBuildApplyScript(manifest);
      expect(script, contains("ln -sf '/root/.cache' '/session/home/.cache'"));
      expect(
        script,
        contains("cp -R -- '/cli-defaults/cursor/.' '/session/cursor'"),
      );
      expect(
        script,
        contains(
          "cp -f -- '/cli-defaults/cursor/settings.json' "
          "'/session/cursor/settings.json'",
        ),
      );
    });

    test('flush applies remove and rename on target', () async {
      final source = InMemoryFilesystem();
      final target = InMemoryFilesystem();
      target.files['/old'] = 'x';
      final manifest = LaunchManifest()
        ..writeFile('/new', 'y')
        ..removeRecursive('/old');

      await const ManifestExecutor().flush(
        manifest: manifest,
        targetFs: target,
        sourceFs: source,
      );

      expect(target.files.containsKey('/old'), isFalse);
      expect(target.files['/new'], 'y');
    });
  });
}
