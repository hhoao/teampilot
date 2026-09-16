import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/launch/launch_manifest.dart';
import 'package:teampilot/services/launch/manifest_ssh_flush_plan.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('same-host plan is one cp script epoch', () async {
    final fs = InMemoryFilesystem();
    final manifest = LaunchManifest()
      ..copyTree(source: '/src/tree', destination: '/dst/tree');
    final epochs = await buildManifestSshFlushPlan(
      manifest: manifest,
      sourceFs: fs,
      workRoot: '/dst',
      sameHost: true,
    );
    expect(epochs, hasLength(1));
    expect(epochs.single.kind, ManifestSshEpochKind.script);
    expect(
      epochs.single.script,
      contains("cp -R -- '/src/tree/.' '/dst/tree'"),
    );
    expect(epochs.single.gzipTar, isNull);
  });

  test('off-home copyTree becomes tar bytes not cat heredoc', () async {
    final fs = InMemoryFilesystem();
    await fs.writeBytes('/home/src/bin.dat', [0, 1, 255]);
    final root = '/work/root';
    final manifest = LaunchManifest()
      ..copyTree(source: '/home/src', destination: '$root/pool/bin');
    final epochs = await buildManifestSshFlushPlan(
      manifest: manifest,
      sourceFs: fs,
      workRoot: root,
      sameHost: false,
    );
    expect(epochs, hasLength(1));
    expect(epochs.single.kind, ManifestSshEpochKind.tar);
    expect(
      epochs.single.extractCommand,
      "mkdir -p '$root' && gzip -dc | tar -x -C '$root'",
    );
    final tar = GZipDecoder().decodeBytes(epochs.single.gzipTar!);
    final decoded = TarDecoder().decodeBytes(tar);
    final file = decoded.findFile('pool/bin/bin.dat')!;
    expect(file.content as List<int>, [0, 1, 255]);
  });

  test('write then remove keeps tar then script order', () async {
    final fs = InMemoryFilesystem();
    const root = '/work/root';
    final manifest = LaunchManifest()
      ..writeFile('$root/a.txt', 'x')
      ..removeRecursive('$root/a.txt');
    final epochs = await buildManifestSshFlushPlan(
      manifest: manifest,
      sourceFs: fs,
      workRoot: root,
      sameHost: false,
    );
    expect(epochs.map((e) => e.kind).toList(), [
      ManifestSshEpochKind.tar,
      ManifestSshEpochKind.script,
    ]);
    expect(epochs[1].script, contains('rm -rf'));
  });

  test('remove then write keeps script then tar order', () async {
    final fs = InMemoryFilesystem();
    const root = '/work/root';
    final manifest = LaunchManifest()
      ..removeRecursive('$root/a.txt')
      ..writeFile('$root/a.txt', 'x');
    final epochs = await buildManifestSshFlushPlan(
      manifest: manifest,
      sourceFs: fs,
      workRoot: root,
      sameHost: false,
    );
    expect(epochs.map((e) => e.kind).toList(), [
      ManifestSshEpochKind.script,
      ManifestSshEpochKind.tar,
    ]);
    expect(epochs[0].script, contains('rm -rf'));
  });

  test('in-root symlink is mutation script not a tar member', () async {
    final fs = InMemoryFilesystem();
    const root = '/work/root';
    final manifest = LaunchManifest()
      ..symlink(linkPath: '$root/home/.npm', target: '$root/pool/npm');
    final epochs = await buildManifestSshFlushPlan(
      manifest: manifest,
      sourceFs: fs,
      workRoot: root,
      sameHost: false,
    );
    expect(epochs, hasLength(1));
    expect(epochs.single.kind, ManifestSshEpochKind.script);
    expect(epochs.single.script, contains("rm -rf -- '$root/home/.npm'"));
    expect(
      epochs.single.script,
      contains("ln -sfn -- '$root/pool/npm' '$root/home/.npm'"),
    );
    expect(epochs.single.gzipTar, isNull);
  });

  test('symlink target over 100 bytes survives as ln -sfn not tar', () async {
    final fs = InMemoryFilesystem();
    const root = '/work/root';
    final target = '$root/pool/${'x' * 120}';
    expect(target.length, greaterThan(100));
    final manifest = LaunchManifest()
      ..symlink(linkPath: '$root/home/.long', target: target);
    final epochs = await buildManifestSshFlushPlan(
      manifest: manifest,
      sourceFs: fs,
      workRoot: root,
      sameHost: false,
    );
    expect(epochs, hasLength(1));
    expect(epochs.single.kind, ManifestSshEpochKind.script);
    expect(epochs.single.script, contains("ln -sfn -- '$target'"));
    expect(epochs.single.gzipTar, isNull);
  });

  test('out-of-root writeFile is heredoc script not tar', () async {
    final fs = InMemoryFilesystem();
    const root = '/work/root';
    final manifest = LaunchManifest()..writeFile('/etc/outside.txt', 'secret');
    final epochs = await buildManifestSshFlushPlan(
      manifest: manifest,
      sourceFs: fs,
      workRoot: root,
      sameHost: false,
    );
    expect(epochs, hasLength(1));
    expect(epochs.single.kind, ManifestSshEpochKind.script);
    expect(epochs.single.script, contains("cat > '/etc/outside.txt'"));
    expect(epochs.single.script, contains('secret'));
    expect(epochs.single.gzipTar, isNull);
  });

  test('out-of-root symlink copies raw bytes into tar', () async {
    final fs = InMemoryFilesystem();
    await fs.writeBytes('/home/alice/.claude.json', [0, 1, 255]);
    const root = '/work/root';
    final manifest = LaunchManifest()
      ..symlink(
        linkPath: '$root/home/.claude.json',
        target: '/home/alice/.claude.json',
      );
    final epochs = await buildManifestSshFlushPlan(
      manifest: manifest,
      sourceFs: fs,
      workRoot: root,
      sameHost: false,
    );
    expect(epochs, hasLength(1));
    expect(epochs.single.kind, ManifestSshEpochKind.tar);
    final tar = GZipDecoder().decodeBytes(epochs.single.gzipTar!);
    final decoded = TarDecoder().decodeBytes(tar);
    final file = decoded.findFile('home/.claude.json')!;
    expect(file.isSymbolicLink, isFalse);
    expect(file.content as List<int>, [0, 1, 255]);
  });

  test('off-home copyFile keeps raw bytes in tar', () async {
    final fs = InMemoryFilesystem();
    await fs.writeBytes('/home/src/bin.dat', [0, 1, 255]);
    const root = '/work/root';
    final manifest = LaunchManifest()
      ..copyFile(
        source: '/home/src/bin.dat',
        destination: '$root/pool/bin.dat',
      );
    final epochs = await buildManifestSshFlushPlan(
      manifest: manifest,
      sourceFs: fs,
      workRoot: root,
      sameHost: false,
    );
    expect(epochs, hasLength(1));
    expect(epochs.single.kind, ManifestSshEpochKind.tar);
    expect(epochs.single.script, isNull);
    final tar = GZipDecoder().decodeBytes(epochs.single.gzipTar!);
    final decoded = TarDecoder().decodeBytes(tar);
    expect(decoded.findFile('pool/bin.dat')!.content as List<int>, [0, 1, 255]);
  });

  test('consecutive in-root writes stay one tar epoch', () async {
    final fs = InMemoryFilesystem();
    const root = '/work/root';
    final manifest = LaunchManifest()
      ..writeFile('$root/a.txt', 'a')
      ..ensureDir('$root/empty')
      ..writeFile('$root/b.txt', 'b');
    final epochs = await buildManifestSshFlushPlan(
      manifest: manifest,
      sourceFs: fs,
      workRoot: root,
      sameHost: false,
    );
    expect(epochs, hasLength(1));
    expect(epochs.single.kind, ManifestSshEpochKind.tar);
    final tar = GZipDecoder().decodeBytes(epochs.single.gzipTar!);
    final decoded = TarDecoder().decodeBytes(tar);
    expect(decoded.findFile('a.txt')!.content as List<int>, 'a'.codeUnits);
    expect(decoded.findFile('b.txt')!.content as List<int>, 'b'.codeUnits);
    expect(decoded.findFile('empty')!.isDirectory, isTrue);
  });
}
