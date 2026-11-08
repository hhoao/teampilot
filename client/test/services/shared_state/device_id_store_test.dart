import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/shared_state/device_id_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('creates and persists a stable device id', () async {
    final fs = InMemoryFilesystem();
    final store = DeviceIdStore(fs: fs, path: '/tp/device-id');

    final first = await store.loadOrCreate();
    final second = await store.loadOrCreate();

    expect(first, isNotEmpty);
    expect(second, first);
    expect(fs.files['/tp/device-id'], first);
  });

  test('replaces an invalid persisted id', () async {
    final fs = InMemoryFilesystem()..files['/tp/device-id'] = 'x';
    final store = DeviceIdStore(
      fs: fs,
      path: '/tp/device-id',
      generate: () => 'device-12345678',
    );

    expect(await store.loadOrCreate(), 'device-12345678');
    expect(fs.files['/tp/device-id'], 'device-12345678');
  });

  test('rejects an invalid generated id', () async {
    final fs = InMemoryFilesystem();
    final store = DeviceIdStore(
      fs: fs,
      path: '/tp/device-id',
      generate: () => 'bad',
    );

    expect(store.loadOrCreate, throwsStateError);
  });
}
