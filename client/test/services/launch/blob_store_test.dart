import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/launch/apply_plan.dart';
import 'package:teampilot/services/launch/blob_store.dart';

void main() {
  test('put then open returns bytes; missing throws', () async {
    final store = MemoryBlobStore();
    final bytes = <int>[0, 1, 255];
    final hash = contentSha256Hex(bytes);
    await store.put(hash, bytes);
    expect(await store.has(hash), isTrue);
    expect(await store.open(hash), bytes);
    expect(store.open('00' * 32), throwsStateError);
  });

  test('open returns a copy; mutating it does not affect subsequent open', () async {
    final store = MemoryBlobStore();
    final bytes = <int>[10, 20, 30];
    final hash = contentSha256Hex(bytes);
    await store.put(hash, bytes);

    final opened = await store.open(hash);
    opened[0] = 99;

    expect(await store.open(hash), bytes);
  });

  test('put with wrong hash throws and does not store', () async {
    final store = MemoryBlobStore();
    expect(
      () => store.put('00' * 32, <int>[1, 2, 3]),
      throwsStateError,
    );
    expect(await store.has('00' * 32), isFalse);
  });
}
