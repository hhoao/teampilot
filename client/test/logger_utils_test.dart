import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/logger_utils.dart';

void main() {
  test('initFileLogging creates app log under app data root', () async {
    final temp = await Directory.systemTemp.createTemp('tp_logs_');
    addTearDown(() async {
      try {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      } on Object {
        // Log file may still be open on Windows.
      }
    });

    await AppLogger.instance.initFileLogging(temp.path);
    AppLogger.instance.i('hello from test');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final logDir = Directory('${temp.path}/logs');
    expect(await logDir.exists(), isTrue);

    final files = await AppLogger.instance.listLogFiles();
    expect(files, isNotEmpty);

    final contents = await File(files.first).readAsString();
    expect(contents, contains('hello from test'));
  });
}
