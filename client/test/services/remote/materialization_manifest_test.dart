import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/remote/materialization_manifest.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('empty by default when no manifest file exists', () async {
    final m = MaterializationManifest(
      fs: InMemoryFilesystem(),
      machineRoot: '/remote',
    );
    expect(await m.load(), isEmpty);
  });

  test('save then load round-trips the hash map', () async {
    final fs = InMemoryFilesystem();
    final m = MaterializationManifest(fs: fs, machineRoot: '/remote');
    await m.save({'cli-defaults/claude/x': 'abc', 'providers/claude/y': 'def'});

    final reloaded =
        await MaterializationManifest(fs: fs, machineRoot: '/remote').load();
    expect(reloaded['cli-defaults/claude/x'], 'abc');
    expect(reloaded['providers/claude/y'], 'def');
    // persisted under <machineRoot>/.materialized.json
    expect((await fs.stat('/remote/.materialized.json')).isFile, isTrue);
  });

  test('hashOf is stable and content-sensitive', () {
    final m = MaterializationManifest(
      fs: InMemoryFilesystem(),
      machineRoot: '/r',
    );
    final a = m.hashOf('hello'.codeUnits);
    expect(a, m.hashOf('hello'.codeUnits)); // stable
    expect(a, isNot(m.hashOf('hello!'.codeUnits))); // content-sensitive
  });
}
