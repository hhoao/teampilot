import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/services/launch/session_init_request_mapper.dart';
import 'package:teampilot_scheduler/teampilot_scheduler.dart';

void main() {
  test(
    'maps LaunchSecurityPolicy.fullAccess to SessionSecurityPolicy.fullAccess',
    () {
      final req = sessionInitRequestFromConnect(
        workspaceId: 'w',
        sessionId: 's',
        memberId: 's',
        cli: 'cursor',
        cliExecutablePath: '/bin/cursor-agent',
        homeRoot: '/h',
        workRoot: '/w',
        securityPolicy: LaunchSecurityPolicy.fullAccess,
      );
      expect(req.securityPolicy.sandbox, SessionSandboxPolicy.fullAccess);
      expect(req.securityPolicy.approval, SessionApprovalPolicy.never);
      expect(req.securityPolicy.hookTrust, SessionHookTrustPolicy.bypass);
      expect(req.cli, 'cursor');
    },
  );

  test('maps LaunchSecurityPolicy fields onto SessionSecurityPolicy', () {
    final req = sessionInitRequestFromConnect(
      workspaceId: 'w',
      sessionId: 's',
      memberId: 's',
      cli: 'claude',
      cliExecutablePath: '/bin/claude',
      homeRoot: '/h',
      workRoot: '/w',
      providerId: 'p',
      identityId: 'i',
      workingDirectory: '/proj',
      additionalDirectories: const ['/extra'],
      cliTeamName: 'team',
      resumeSessionId: 'resume',
      createSessionId: 'create',
      securityPolicy: LaunchSecurityPolicy.askReadOnlyTrusted,
      skillIds: const ['sk'],
      pluginIds: const ['pl'],
      mcpIds: const ['mcp'],
    );
    expect(req.securityPolicy.approval, SessionApprovalPolicy.ask);
    expect(req.securityPolicy.sandbox, SessionSandboxPolicy.readOnly);
    expect(req.securityPolicy.hookTrust, SessionHookTrustPolicy.trustedOnly);
    expect(req.providerId, 'p');
    expect(req.identityId, 'i');
    expect(req.workingDirectory, '/proj');
    expect(req.additionalDirectories, ['/extra']);
    expect(req.cliTeamName, 'team');
    expect(req.resumeSessionId, 'resume');
    expect(req.createSessionId, 'create');
    expect(req.skillIds, ['sk']);
    expect(req.pluginIds, ['pl']);
    expect(req.mcpIds, ['mcp']);
  });
}
