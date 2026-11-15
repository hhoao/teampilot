import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/services/acp/acp_proxy_session_meta.dart';

void main() {
  test('merge keeps claudeCode and adds the proxy launch block', () {
    final meta = mergeAcpProxySessionMeta(
      base: const {
        'claudeCode': {
          'options': {
            'disallowedTools': ['ListAgents'],
          },
        },
      },
      cli: 'claude',
      argv: const ['claude-agent-acp', '--verbose'],
      env: const {'HOME': '/home/u', 'ANTHROPIC_API_KEY': ''},
      permissionPolicy: LaunchSecurityPolicy.ask,
      authenticateMethodId: '  oauth  ',
    );

    expect(meta['claudeCode'], {
      'options': {
        'disallowedTools': ['ListAgents'],
      },
    });
    expect(meta['teampilot'], {
      'cli': 'claude',
      'executable': 'claude-agent-acp',
      'args': ['--verbose'],
      'env': {'HOME': '/home/u', 'ANTHROPIC_API_KEY': ''},
      'permissionPolicy': 'ask',
      'authenticateMethodId': 'oauth',
    });
  });

  test('full access omits an empty authenticate method', () {
    final meta = mergeAcpProxySessionMeta(
      base: const {},
      cli: 'gemini',
      argv: const ['gemini', '--acp'],
      env: const {},
      permissionPolicy: LaunchSecurityPolicy.fullAccess,
      authenticateMethodId: '   ',
    );

    final teampilot = meta['teampilot']! as Map<String, Object?>;
    expect(teampilot['permissionPolicy'], 'fullAccess');
    expect(teampilot.containsKey('authenticateMethodId'), isFalse);
  });

  test('empty argv is rejected', () {
    expect(
      () => mergeAcpProxySessionMeta(
        base: const {},
        cli: 'gemini',
        argv: const [],
        env: const {},
        permissionPolicy: LaunchSecurityPolicy.fullAccess,
      ),
      throwsArgumentError,
    );
  });
}
