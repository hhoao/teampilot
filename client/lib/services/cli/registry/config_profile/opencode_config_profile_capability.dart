import '../capabilities/config_profile_capability.dart';

final class OpencodeConfigProfileCapability implements ConfigProfileCapability {
  const OpencodeConfigProfileCapability();

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    return ConfigProfileLaunchContribution(
      environment: {
        'OPENCODE': ctx.paths.sessionToolDir(
          ctx.scope.teamId,
          ctx.scope.sessionId,
          'opencode',
        ),
      },
    );
  }
}
