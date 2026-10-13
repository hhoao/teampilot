import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_host_mcp_permission.dart';

void main() {
  test('Ask mode auto-allows teammate-bus but not bash', () {
    final bus = {
      'toolCall': {'title': 'teammate-bus-read_messages: read_messages'},
      'options': [
        {'optionId': 'always-1', 'kind': 'allow-always'},
      ],
    };
    final bash = {
      'toolCall': {'title': 'Run npm install'},
      'options': [
        {'optionId': 'always-1', 'kind': 'allow-always'},
      ],
    };
    expect(
      autoAllowAcpPermissionOptionId(bus, allowNonHost: false),
      'always-1',
    );
    expect(autoAllowAcpPermissionOptionId(bash, allowNonHost: false), isNull);
    expect(
      autoAllowAcpPermissionOptionId(bash, allowNonHost: true),
      'always-1',
    );
  });

  test('prefers allow-always over allow-once', () {
    expect(
      autoAllowAcpPermissionOptionId({
        'options': [
          {'optionId': 'once-1', 'kind': 'allow-once'},
          {'optionId': 'always-1', 'kind': 'allow-always'},
        ],
      }),
      'always-1',
    );
  });

  test('falls back to allow-once when no allow-always is present', () {
    expect(
      autoAllowAcpPermissionOptionId({
        'options': [
          {'optionId': 'reject-1', 'kind': 'reject-once'},
          {'optionId': 'once-1', 'kind': 'allow_once'},
        ],
      }),
      'once-1',
    );
  });

  test('accepts hyphen and underscore kinds from raw JSON', () {
    expect(
      autoAllowAcpPermissionOptionId({
        'options': [
          {'optionId': 'hyphen', 'kind': 'allow-always'},
        ],
      }),
      'hyphen',
    );
    expect(
      autoAllowAcpPermissionOptionId({
        'options': [
          {'optionId': 'underscore', 'kind': 'allow_always'},
        ],
      }),
      'underscore',
    );
  });

  test('accepts optionId, option_id, and id', () {
    expect(
      autoAllowAcpPermissionOptionId({
        'options': [
          {'option_id': 'snake', 'kind': 'allow-once'},
        ],
      }),
      'snake',
    );
    expect(
      autoAllowAcpPermissionOptionId({
        'options': [
          {'id': 'short', 'kind': 'allow-once'},
        ],
      }),
      'short',
    );
  });

  test('reject-only options are not auto-allowed', () {
    expect(
      autoAllowAcpPermissionOptionId({
        'toolCall': {'title': 'Run npm install'},
        'options': [
          {'optionId': 'reject-1', 'kind': 'reject-once'},
          {'optionId': 'reject-2', 'kind': 'reject_always'},
        ],
      }),
      isNull,
    );
  });

  test('reads snake_case tool_call title and rawInput for host gating', () {
    final viaRaw = {
      'tool_call': {
        'raw_input': {'server': 'teammate-bus'},
      },
      'options': [
        {'optionId': 'always-1', 'kind': 'allow-always'},
      ],
    };
    expect(
      autoAllowAcpPermissionOptionId(viaRaw, allowNonHost: false),
      'always-1',
    );
  });
}
