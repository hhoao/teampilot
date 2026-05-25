import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/session_launch_error.dart';

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

  test('formatSessionLaunchError truncates long messages', () {
    final raw = List<String>.generate(6, (i) => 'line $i').join('\n');
    final formatted = formatSessionLaunchError(raw);
    expect(formatted.endsWith('…'), isTrue);
    expect(formatted.split('\n').length, lessThanOrEqualTo(5));
  });
}
