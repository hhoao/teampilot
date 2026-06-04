import '../cli_capability.dart';
import '../config_profile/config_profile_context.dart';

export '../config_profile/config_profile_context.dart';

/// Tool-specific session profile setup and launch environment contribution.
abstract interface class ConfigProfileCapability implements CliCapability {
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx);

  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  );
}

class ConfigProfileLaunchContribution {
  const ConfigProfileLaunchContribution({
    this.environment = const {},
    this.warnings = const [],
  });

  final Map<String, String> environment;
  final List<String> warnings;
}
