import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/general_permission_request_gate.dart';

void main() {
  test('allow reply renders the official decision object', () {
    final reply = GeneralPermissionRequestReply.allow(
      updatedPermissions: [
        {
          'type': 'addRules',
          'rules': [
            {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
          ],
          'behavior': 'allow',
          'destination': 'localSettings',
        },
      ],
    );
    expect(reply.toHookResponse(), {
      'hookSpecificOutput': {
        'hookEventName': 'PermissionRequest',
        'decision': {
          'behavior': 'allow',
          'updatedPermissions': [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
              ],
              'behavior': 'allow',
              'destination': 'localSettings',
            },
          ],
        },
      },
    });
  });

  test('plain allow omits updatedPermissions', () {
    expect(
      const GeneralPermissionRequestReply.allow().toHookResponse(),
      {
        'hookSpecificOutput': {
          'hookEventName': 'PermissionRequest',
          'decision': {'behavior': 'allow'},
        },
      },
    );
  });

  test('deny reply carries the message', () {
    expect(
      const GeneralPermissionRequestReply.deny('User denied via TeamPilot')
          .toHookResponse(),
      {
        'hookSpecificOutput': {
          'hookEventName': 'PermissionRequest',
          'decision': {
            'behavior': 'deny',
            'message': 'User denied via TeamPilot',
          },
        },
      },
    );
  });

  test('gate hold/complete/releaseHold lifecycle', () async {
    final gate = GeneralPermissionRequestGate();
    final held = gate.wait(sessionId: 's', memberId: 'm');
    expect(gate.hasWaiter(sessionId: 's', memberId: 'm'), isTrue);
    expect(
      gate.complete(
        sessionId: 's',
        memberId: 'm',
        reply: const GeneralPermissionRequestReply.allow(),
      ),
      isTrue,
    );
    expect(await held, isA<GeneralPermissionRequestReply>());
    expect(gate.hasWaiter(sessionId: 's', memberId: 'm'), isFalse);
  });

  test('releaseHold falls through to the native TUI', () async {
    final gate = GeneralPermissionRequestGate();
    final held = gate.wait(sessionId: 's', memberId: 'm');
    expect(gate.releaseHold(sessionId: 's', memberId: 'm'), isTrue);
    expect(await held, isNull);
  });

  test('a newer wait denies the previous held request', () async {
    final gate = GeneralPermissionRequestGate();
    final first = gate.wait(sessionId: 's', memberId: 'm');
    gate.wait(sessionId: 's', memberId: 'm');
    final reply = await first;
    expect(reply, isNotNull);
    expect(reply!.deny, isTrue);
  });
}
