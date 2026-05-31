import '../capabilities/config_profile_capability.dart';

final class CodexConfigProfileCapability implements ConfigProfileCapability {
  const CodexConfigProfileCapability();

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    return ConfigProfileLaunchContribution(
      environment: {
        'CODEX_HOME': ctx.paths.sessionToolDir(
          ctx.scope.teamId,
          ctx.scope.sessionId,
          'codex',
        ),
      },
    );
  }
}
