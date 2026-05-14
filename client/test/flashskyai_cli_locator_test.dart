import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/flashskyai_cli_locator.dart';

void main() {
  test('locate returns native path from PATH lookup', () async {
    final located = await FlashskyaiCliLocator.locate(
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        return ProcessResult(1, 0, '/opt/bin/flashskyai\n', '');
      },
    );

    expect(located, '/opt/bin/flashskyai');
  });

  test('locate falls back to WSL on Windows', () async {
    if (!Platform.isWindows) return;
    final calls = <String>[];
    final located = await FlashskyaiCliLocator.locate(
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        calls.add('$executable ${arguments.join(' ')}');
        if (executable == 'where') {
          return ProcessResult(1, 1, '', '');
        }
        expect(stdoutEncoding, utf8);
        expect(stderrEncoding, utf8);
        return ProcessResult(2, 0, '/usr/local/bin/flashskyai\n', '');
      },
    );

    expect(calls, ['where flashskyai', 'wsl.exe bash -ilc command -v flashskyai']);
    expect(located, 'wsl.exe /usr/local/bin/flashskyai');
  });

  test('locate WSL path skips wsl stdout noise lines on Windows', () async {
    if (!Platform.isWindows) return;
    final located = await FlashskyaiCliLocator.locate(
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        if (executable == 'where') {
          return ProcessResult(1, 1, '', '');
        }
        return ProcessResult(
          2,
          0,
          'wsl: 检测到 localhost 代理配置，但未镜像到 WSL。\n'
              '/home/hhoa/dist/flashskyai\n',
          '',
        );
      },
    );

    expect(located, 'wsl.exe /home/hhoa/dist/flashskyai');
  });
}
