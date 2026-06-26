import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/launch/launch_manifest.dart';
import 'package:teampilot/services/launch/manifest_executor.dart';
import 'package:teampilot/services/launch/manifest_filesystem.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  group('ManifestFilesystem', () {
    test('removeRecursive stages op without mutating readDelegate', () async {
      final home = InMemoryFilesystem();
      const path = '/teampilot/workspace/ws/sessions/s1/runtime/claude/creds.json';
      home.files[path] = 'home-secret';

      final manifest = LaunchManifest();
      final staging = ManifestFilesystem(
        manifest: manifest,
        readDelegate: home,
      );

      await staging.removeRecursive(path);

      expect(home.files[path], 'home-secret');
      expect(
        manifest.entries.whereType<ManifestRemoveRecursive>().map((e) => e.path),
        [path],
      );
    });

    test('rename from readDelegate copies into manifest without mutating home',
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
      expect(
        manifest.entries.whereType<ManifestRemoveRecursive>().length,
        1,
      );
    });
  });

  group('ManifestExecutor', () {
    test('flush throws when copy source is missing across filesystems', () async {
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
    });

    test('ssh script heredoc delimiter avoids content collision', () {
      const content = 'data __TP_MANIFEST_42__ tail';
      final manifest = LaunchManifest()..writeFile('/tmp/out', content);
      final script = ManifestExecutor.debugBuildApplyScript(manifest);
      expect(script, contains(content));
      expect(script.split("<<'").length, greaterThan(1));
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
