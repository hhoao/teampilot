import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/logging/logger_utils.dart';

Future<String> _readLogWhenContains(String path, String needle) async {
  final file = File(path);
  for (var attempt = 0; attempt < 40; attempt++) {
    if (await file.exists()) {
      final contents = await file.readAsString();
      if (contents.contains(needle)) return contents;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (!await file.exists()) return '';
  return file.readAsString();
}

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
    AppLogger.instance.d('trace from test');
    await AppLogger.instance.flushFileLogging();

    final logDir = Directory('${temp.path}/logs');
    expect(await logDir.exists(), isTrue);

    final logPath = AppLogger.instance.currentLogFilePath;
    expect(logPath, isNotNull);

    final files = await AppLogger.instance.listLogFiles();
    expect(files, isNotEmpty);
    expect(files.first, logPath);

    final contents = await _readLogWhenContains(logPath!, 'hello from test');
    expect(contents, contains('hello from test'));
    expect(contents, contains('trace from test'));
    expect(
      contents,
      matches(
        RegExp(
          r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \|  INFO \d+ \| [^\|]+\.dart:\d+:\d+ \| hello from test',
        ),
      ),
    );

    // A chatty burst (ACP frame mirroring is one line per streamed token) is
    // buffered and lands in order on the next flush, without one blocking
    // write-with-flush per line.
    for (var i = 0; i < 200; i++) {
      AppLogger.instance.i('burst line $i');
    }
    await AppLogger.instance.flushFileLogging();

    final afterBurst = await File(logPath).readAsString();
    expect(afterBurst, contains('burst line 0\n'));
    expect(afterBurst, contains('burst line 199'));
    expect(
      afterBurst.indexOf('burst line 0\n'),
      lessThan(afterBurst.indexOf('burst line 199')),
    );
  });
}
