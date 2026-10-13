import '../../../../models/launch_security_policy.dart';
import '../cli_capability.dart';

abstract interface class CliLaunchSecurityCapability implements CliCapability {
  bool get supportsUserConfiguration;
  Set<LaunchSecurityPolicy> get supportedPolicies;
  Set<LaunchSecurityPolicy> policiesFor({required bool acp});
  bool supportsUserConfigurationFor({required bool acp});
}

final class FullAccessOnlyCliLaunchSecurityCapability
    implements CliLaunchSecurityCapability {
  const FullAccessOnlyCliLaunchSecurityCapability();

  static final Set<LaunchSecurityPolicy> _supportedPolicies = Set.unmodifiable({
    LaunchSecurityPolicy.fullAccess,
  });

  @override
  bool get supportsUserConfiguration => false;

  @override
  Set<LaunchSecurityPolicy> get supportedPolicies => _supportedPolicies;

  @override
  Set<LaunchSecurityPolicy> policiesFor({required bool acp}) =>
      _supportedPolicies;

  @override
  bool supportsUserConfigurationFor({required bool acp}) =>
      policiesFor(acp: acp).length > 1;
}

final class AcpAskFullAccessCliLaunchSecurityCapability
    implements CliLaunchSecurityCapability {
  const AcpAskFullAccessCliLaunchSecurityCapability();

  static final Set<LaunchSecurityPolicy> _pty = Set.unmodifiable({
    LaunchSecurityPolicy.fullAccess,
  });
  static final Set<LaunchSecurityPolicy> _acp = Set.unmodifiable({
    LaunchSecurityPolicy.ask,
    LaunchSecurityPolicy.fullAccess,
  });

  @override
  bool get supportsUserConfiguration => false;

  @override
  Set<LaunchSecurityPolicy> get supportedPolicies => _pty;

  @override
  Set<LaunchSecurityPolicy> policiesFor({required bool acp}) =>
      acp ? _acp : _pty;

  @override
  bool supportsUserConfigurationFor({required bool acp}) =>
      policiesFor(acp: acp).length > 1;
}
