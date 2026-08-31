import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/session/session_launch_error.dart';

void main() {
  test('formatSessionLaunchError strips brackets and normalizes lines', () {
    const raw =
        '[无法启动 claude: executable not found\n'
        '  /missing/claude\n'
        '  Open Settings → Session]';

    expect(
      formatSessionLaunchError(raw),
      '无法启动 claude: executable not found\n'
      '/missing/claude\n'
      'Open Settings → Session',
    );
  });

  test('formatSessionLaunchError rewrites glibc linker errors', () {
    const raw =
        "/root/.local/bin/cursor-agent: /lib64/libc.so.6: version `GLIBC_2.28' "
        'not found (required by /root/.local/bin/cursor-agent)';
    final formatted = formatSessionLaunchError(raw);
    expect(formatted, contains('glibc'));
    expect(formatted, contains('2.28'));
    expect(formatted, isNot(contains('version `GLIBC_2.28\'')));
  });

  test('formatSessionLaunchError keeps long multi-line detail logs', () {
    final raw = List<String>.generate(12, (i) => 'line $i').join('\n');
    final formatted = formatSessionLaunchError(raw);
    expect(formatted.endsWith('…'), isFalse);
    expect(formatted.split('\n'), hasLength(12));
    expect(formatted, contains('line 11'));
  });

  test('formatSessionLaunchError soft-caps extremely long dumps', () {
    final raw = List<String>.generate(
      kSessionLaunchErrorMaxDetailLines + 20,
      (i) => 'line $i',
    ).join('\n');
    final formatted = formatSessionLaunchError(raw);
    expect(formatted.endsWith('…'), isTrue);
    expect(
      formatted.split('\n').length,
      kSessionLaunchErrorMaxDetailLines + 1,
    );
  });

  test('formatSessionLaunchError keeps PTY stderr above the exit stub', () {
    const raw =
        'Error: [unavailable] connect ETIMEDOUT 28.0.0.8:443\n\n'
        '[process exited with code 1]';
    final formatted = formatSessionLaunchError(raw);
    expect(formatted, contains('ETIMEDOUT 28.0.0.8:443'));
    expect(formatted, contains('process exited with code 1'));
  });
}
