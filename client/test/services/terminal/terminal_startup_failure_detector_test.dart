import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_startup_failure_detector.dart';

const _cursorGlibcLinkerError = r'''
/root/.local/bin/cursor-agent: /lib64/libstdc++.so.6: version `CXXABI_1.3.11' not found (required by /root/.local/bin/cursor-agent)
/root/.local/bin/cursor-agent: /lib64/libc.so.6: version `GLIBC_2.28' not found (required by /root/.local/bin/cursor-agent)
''';

void main() {
  test('classifies dynamic-linker glibc / libstdc++ version errors', () {
    expect(
      TerminalStartupFailureDetector.looksLikeGlibcIncompatibility(
        _cursorGlibcLinkerError,
      ),
      isTrue,
    );
    expect(
      TerminalStartupFailureDetector.looksLikeExecFailure(
        _cursorGlibcLinkerError,
      ),
      isFalse,
    );
  });

  test(
    'startup classify explains glibc 2.28 instead of missing executable',
    () {
      final message = TerminalStartupFailureDetector.classifyStartupFailure(
        _cursorGlibcLinkerError,
        executable: '/root/.local/bin/cursor-agent',
        validateLaunch: false,
      );
      expect(message, isNotNull);
      expect(message, contains('glibc'));
      expect(message, contains('2.28'));
      expect(message, isNot(contains('未找到可执行文件')));
    },
  );

  test('does not treat normal CLI output as a glibc incompatibility', () {
    expect(
      TerminalStartupFailureDetector.looksLikeGlibcIncompatibility(
        'Cursor Agent\nready\n',
      ),
      isFalse,
    );
    expect(
      TerminalStartupFailureDetector.classifyStartupFailure(
        'Cursor Agent\nready\n',
        executable: 'cursor-agent',
        validateLaunch: true,
      ),
      isNull,
    );
  });
}
