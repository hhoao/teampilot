import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory dir;
  late LocalFilesystem fs;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tp-fs-range-');
    fs = LocalFilesystem();
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('range read and append round-trip', () async {
    final path = '${dir.path}/f.bin';
    await fs.writeBytes(path, [10, 20, 30, 40]);
    expect(await fs.readBytesRange(path, 1, 2), [20, 30]);
    await fs.appendBytes(path, [50]);
    expect(await fs.readBytes(path), [10, 20, 30, 40, 50]);
  });
}
