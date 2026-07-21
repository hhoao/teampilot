import 'package:flutter_test/flutter_test.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  test('readBytesRange returns slice and fewer bytes at EOF', () async {
    final fs = InMemoryFilesystem();
    await fs.writeBytes('/a.bin', [0, 1, 2, 3, 4]);
    expect(await fs.readBytesRange('/a.bin', 1, 2), [1, 2]);
    expect(await fs.readBytesRange('/a.bin', 3, 10), [3, 4]);
    expect(await fs.readBytesRange('/a.bin', 5, 4), <int>[]);
    expect(await fs.readBytesRange('/missing', 0, 4), isNull);
  });

  test('appendBytes creates and extends', () async {
    final fs = InMemoryFilesystem();
    await fs.appendBytes('/a.bin', [1, 2]);
    await fs.appendBytes('/a.bin', [3]);
    expect(await fs.readBytes('/a.bin'), [1, 2, 3]);
  });
}
