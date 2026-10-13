import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_host_mcp_permission.dart';

void main() {
  test('hyphenated Cursor kinds auto-allow allow-always optionId', () {
    expect(
      autoAllowAcpPermissionOptionId({
        'sessionId': 's',
        'toolCall': {
          'toolCallId': 't',
          'title': 'teammate-bus-read_messages: read_messages',
        },
        'options': [
          {
            'optionId': 'allow-once',
            'name': 'Allow once',
            'kind': 'allow-once',
          },
          {
            'optionId': 'allow-always',
            'name': 'Allow always',
            'kind': 'allow-always',
          },
          {
            'optionId': 'reject-once',
            'name': 'Reject',
            'kind': 'reject-once',
          },
        ],
      }),
      'allow-always',
    );
  });

  test('underscore kinds still prefer allow_always', () {
    expect(
      autoAllowAcpPermissionOptionId({
        'sessionId': 's',
        'toolCall': {'toolCallId': 't', 'title': 'bash'},
        'options': [
          {'optionId': 'allow-1', 'name': 'Allow once', 'kind': 'allow_once'},
          {
            'optionId': 'always-1',
            'name': 'Allow always',
            'kind': 'allow_always',
          },
        ],
      }),
      'always-1',
    );
  });

  test('reject-only options are not auto-allowed', () {
    expect(
      autoAllowAcpPermissionOptionId({
        'sessionId': 's',
        'toolCall': {'toolCallId': 't', 'title': 'bash'},
        'options': [
          {'optionId': 'reject-1', 'name': 'Reject', 'kind': 'reject_once'},
        ],
      }),
      isNull,
    );
  });
}
