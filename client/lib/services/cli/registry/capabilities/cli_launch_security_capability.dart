import '../../../../models/launch_security_policy.dart';
import '../cli_capability.dart';

abstract interface class CliLaunchSecurityCapability implements CliCapability {
  bool get supportsUserConfiguration;
  Set<LaunchSecurityPolicy> get supportedPolicies;
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
}
