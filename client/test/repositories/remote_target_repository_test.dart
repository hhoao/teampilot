import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/remote_target.dart';
import 'package:teampilot/repositories/remote_target_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late RemoteTargetRepository repo;

  setUp(() {
    fs = InMemoryFilesystem();
    repo = RemoteTargetRepository(rootDir: '/tp', fs: fs);
  });

  test('saves and loads a target', () async {
    const target = RemoteTarget(
      id: 't1',
      name: 'dev',
      host: 'h',
      username: 'u',
    );
    await repo.save(target);
    final loaded = await repo.loadAll();
    expect(loaded, [target]);
  });

  test('updates existing target by id', () async {
    await repo.save(
      const RemoteTarget(id: 't1', name: 'a', host: 'h', username: 'u'),
    );
    await repo.save(
      const RemoteTarget(id: 't1', name: 'b', host: 'h', username: 'u'),
    );
    final loaded = await repo.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.name, 'b');
  });

  test('deletes target', () async {
    await repo.save(
      const RemoteTarget(id: 't1', name: 'a', host: 'h', username: 'u'),
    );
    await repo.delete('t1');
    expect(await repo.loadAll(), isEmpty);
  });

  test('returns empty when file is missing', () async {
    expect(await repo.loadAll(), isEmpty);
  });

  test('preserves an unparseable catalog instead of overwriting it', () async {
    const original =
        '[{"schemaVersion":1,"id":"old","name":"legacy","host":"h",'
        '"username":"u","port":"not-a-number"}]';
    await fs.writeString('/tp/remote-targets.json', original);

    await repo.save(
      const RemoteTarget(id: 'new', name: 'new', host: 'h', username: 'u'),
    );

    final loaded = await repo.loadAll();
    expect(loaded.map((t) => t.id), ['new']);
    expect(
      await fs.readString('/tp/remote-targets.corrupt.json'),
      original,
      reason: 'the unreadable file must survive for recovery',
    );
  });
}
