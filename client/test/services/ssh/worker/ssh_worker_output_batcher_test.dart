import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_output_batcher.dart';

void main() {
  test('coalesces output by interval and splits frames at the byte limit', () {
    fakeAsync((async) {
      final batcher = SshWorkerOutputBatcher(
        flushInterval: const Duration(milliseconds: 10),
        maxBytes: 4,
      );
      final output = <Uint8List>[];
      batcher.output.listen(output.add);

      batcher.add(Uint8List.fromList([1, 2, 3]));
      batcher.add(Uint8List.fromList([4, 5, 6]));

      expect(output.map((bytes) => bytes.toList()), [
        [1, 2, 3, 4],
      ]);
      async.elapse(const Duration(milliseconds: 10));
      expect(output.map((bytes) => bytes.toList()), [
        [1, 2, 3, 4],
        [5, 6],
      ]);
    });
  });
}
