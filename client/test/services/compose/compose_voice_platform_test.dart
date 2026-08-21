import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_voice_platform.dart';

void main() {
  group('isMacOsIdeSpawnedProcessFromEnv', () {
    test('detects VS Code / Cursor debug parent', () {
      expect(
        isMacOsIdeSpawnedProcessFromEnv(const {'VSCODE_PID': '12345'}),
        isTrue,
      );
      expect(
        isMacOsIdeSpawnedProcessFromEnv(const {'VSCODE_INJECTION': '1'}),
        isTrue,
      );
      expect(
        isMacOsIdeSpawnedProcessFromEnv(const {'TERM_PROGRAM': 'vscode'}),
        isTrue,
      );
    });

    test('allows direct app launch environments', () {
      expect(isMacOsIdeSpawnedProcessFromEnv(const {}), isFalse);
      expect(
        isMacOsIdeSpawnedProcessFromEnv(const {'TERM_PROGRAM': 'Apple_Terminal'}),
        isFalse,
      );
    });
  });
}
