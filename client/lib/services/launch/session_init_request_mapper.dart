import 'package:teampilot_scheduler/teampilot_scheduler.dart'
    show
        SessionApprovalPolicy,
        SessionHookTrustPolicy,
        SessionInitRequest,
        SessionSandboxPolicy,
        SessionSecurityPolicy;

import '../../models/launch_security_policy.dart';

SessionInitRequest sessionInitRequestFromConnect({
  required String workspaceId,
  required String sessionId,
  required String memberId,
  required String cli,
  required String cliExecutablePath,
  required String homeRoot,
  required String workRoot,
  String providerId = '',
  String identityId = '',
  String workingDirectory = '',
  List<String> additionalDirectories = const [],
  String cliTeamName = '',
  String? resumeSessionId,
  String? createSessionId,
  required LaunchSecurityPolicy securityPolicy,
  List<String> skillIds = const [],
  List<String> pluginIds = const [],
  List<String> mcpIds = const [],
}) {
  return SessionInitRequest(
    workspaceId: workspaceId,
    sessionId: sessionId,
    memberId: memberId,
    cli: cli,
    cliExecutablePath: cliExecutablePath,
    homeRoot: homeRoot,
    workRoot: workRoot,
    providerId: providerId,
    identityId: identityId,
    workingDirectory: workingDirectory,
    additionalDirectories: additionalDirectories,
    cliTeamName: cliTeamName,
    resumeSessionId: resumeSessionId,
    createSessionId: createSessionId,
    securityPolicy: sessionSecurityPolicyFromLaunch(securityPolicy),
    skillIds: skillIds,
    pluginIds: pluginIds,
    mcpIds: mcpIds,
  );
}

SessionSecurityPolicy sessionSecurityPolicyFromLaunch(
  LaunchSecurityPolicy policy,
) {
  return SessionSecurityPolicy(
    approval: switch (policy.approval) {
      LaunchApprovalPolicy.cliDefault => SessionApprovalPolicy.cliDefault,
      LaunchApprovalPolicy.ask => SessionApprovalPolicy.ask,
      LaunchApprovalPolicy.autoApprove => SessionApprovalPolicy.autoApprove,
      LaunchApprovalPolicy.never => SessionApprovalPolicy.never,
    },
    sandbox: switch (policy.sandbox) {
      LaunchSandboxPolicy.cliDefault => SessionSandboxPolicy.cliDefault,
      LaunchSandboxPolicy.readOnly => SessionSandboxPolicy.readOnly,
      LaunchSandboxPolicy.workspaceWrite => SessionSandboxPolicy.workspaceWrite,
      LaunchSandboxPolicy.fullAccess => SessionSandboxPolicy.fullAccess,
    },
    hookTrust: switch (policy.hookTrust) {
      LaunchHookTrustPolicy.cliDefault => SessionHookTrustPolicy.cliDefault,
      LaunchHookTrustPolicy.trustedOnly => SessionHookTrustPolicy.trustedOnly,
      LaunchHookTrustPolicy.bypass => SessionHookTrustPolicy.bypass,
    },
  );
}
