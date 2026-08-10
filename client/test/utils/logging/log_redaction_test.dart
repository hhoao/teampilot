import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/logging/log_redaction.dart';

void main() {
  group('stringifyEnvironmentForLog', () {
    test('keeps benign values visible', () {
      final out = stringifyEnvironmentForLog(const {
        'OPENCODE_CONFIG_DIR': '/tmp/config',
        'HOME': '/home/user',
      });
      expect(out, contains('OPENCODE_CONFIG_DIR=/tmp/config'));
      expect(out, contains('HOME=/home/user'));
    });

    test('redacts values under sensitive key names', () {
      final out = stringifyEnvironmentForLog(const {
        'OPENCODE_AUTH_CONTENT': '{"opencode-go":{"type":"api","key":"sk-abcd"}}',
        'ANTHROPIC_API_KEY': 'sk-ant-1234567890',
        'GITHUB_TOKEN': 'ghp_abcdefghijklmnopqrstuvwxyz1234567890',
      });
      expect(out, isNot(contains('sk-abcd')));
      expect(out, isNot(contains('sk-ant-1234567890')));
      expect(out, isNot(contains('ghp_abcdefghijklmnopqrstuvwxyz1234567890')));
      expect(out, contains('OPENCODE_AUTH_CONTENT=<redacted('));
      expect(out, contains('ANTHROPIC_API_KEY=<redacted('));
      expect(out, contains('GITHUB_TOKEN=<redacted('));
    });

    test('keeps entry length hint so populated vars are distinguishable', () {
      final out = stringifyEnvironmentForLog(const {'OPENCODE_AUTH_CONTENT': 'abcde'});
      expect(out, contains('OPENCODE_AUTH_CONTENT=<redacted(len=5)>'));
    });

    test('redacts credential-looking values under innocent key names', () {
      final out = stringifyEnvironmentForLog(const {
        'LLM_CONFIG': 'sk-proj-someLongSecretValue',
        'CUSTOM_VAR': 'Bearer abc.def.ghi',
      });
      expect(out, isNot(contains('sk-proj-someLongSecretValue')));
      expect(out, isNot(contains('abc.def.ghi')));
    });

    test('handles null and empty maps', () {
      expect(stringifyEnvironmentForLog(null), '');
      expect(stringifyEnvironmentForLog(const {}), '');
    });
  });
}
