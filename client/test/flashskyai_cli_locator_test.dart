import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/flashskyai_cli_locator.dart';

void main() {
  test('locate returns native path from PATH lookup', () async {
    final located = await FlashskyaiCliLocator.locate(
      runner: (executable, arguments) async {
        return ProcessResult(1, 0, '/opt/bin/flashskyai\n', '');
      },
    );

    expect(located, '/opt/bin/flashskyai');
  });

  test('locate falls back to WSL on Windows', () async {
    if (!Platform.isWindows) return;
    final calls = <String>[];
    final located = await FlashskyaiCliLocator.locate(
      runner: (executable, arguments) async {
        calls.add('$executable ${arguments.join(' ')}');
        if (executable == 'where') {
          return ProcessResult(1, 1, '', '');
        }
        return ProcessResult(2, 0, '/usr/local/bin/flashskyai\n', '');
      },
    );

    expect(calls, ['where flashskyai', 'wsl.exe sh -lc command -v flashskyai']);
    expect(located, 'wsl.exe /usr/local/bin/flashskyai');
  });
}
