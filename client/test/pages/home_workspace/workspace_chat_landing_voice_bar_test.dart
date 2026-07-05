import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing_voice_bar.dart';

void main() {
  test('formatComposeVoiceElapsed renders mm:ss', () {
    expect(
      formatComposeVoiceElapsed(const Duration(minutes: 1, seconds: 5)),
      '01:05',
    );
    expect(formatComposeVoiceElapsed(Duration.zero), '00:00');
  });
}
