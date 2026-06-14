import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource/link_strategy.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('link creates an accessible entry (symlink or copy fallback)', () async {
    final fs = AppStorage.fs;
    final tmp = await fs.createTempDir(prefix: 'link_test_');
    final src = fs.pathContext.join(tmp, 'src');
    final dst = fs.pathContext.join(tmp, 'dst');
    await fs.ensureDir(src);
    await fs.writeString(fs.pathContext.join(src, 'f.txt'), 'hello');

    final strategy = LinkStrategy(fs);
    await strategy.link(source: src, target: dst);

    final read = await fs.readString(fs.pathContext.join(dst, 'f.txt'));
    expect(read, 'hello');
  });
}
