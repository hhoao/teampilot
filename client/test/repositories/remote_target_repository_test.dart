import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/remote_target.dart';
import 'package:teampilot/repositories/remote_target_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late RemoteTargetRepository repo;

  setUp(() {
    repo = RemoteTargetRepository(rootDir: '/tp', fs: InMemoryFilesystem());
  });

  test('saves and loads a target', () async {
    const target = RemoteTarget(id: 't1', name: 'dev', host: 'h', username: 'u');
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
}
