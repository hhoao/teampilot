import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../cli/registry/capabilities/installer_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/remote_cli_installer.dart';
import '../cli/remote_cli_locator.dart';
import '../ssh/ssh_client_factory.dart';
import '../storage/runtime_context.dart';
import 'remote_app_data_materializer.dart';
import 'remote_member_preflight_coordinator.dart';
import 'remote_preflight_service.dart';

/// Builds the production [RemoteMemberPreflightCoordinator] by composing the real
/// P3c services (P3c §3.5). DI-injected from app_shell. The only pieces that
/// touch a live host are inside the step closures (SSH exec / SFTP) — those are
/// on-device smoke; the orchestration + decision logic are fake-covered by the
/// per-service unit tests.
///
/// Bus binding is intentionally **not** done here: the per-tab
/// `RemoteBusBindingResolver` (which owns the session's bus server) binds the
/// tunnel for every ssh member (home-ssh and off-home alike).
RemoteMemberPreflightCoordinator buildRemoteMemberPreflightCoordinator({
  required CliToolRegistry registry,
  required SshClientFactory sshClientFactory,
  required SshProfile? Function(String profileId) profileById,
  required Future<RuntimeContext> Function(RuntimeTarget target) contextForTarget,
  required RuntimeContext Function() homeContext,
  required RuntimeTarget Function() homeTarget,
  required Future<bool> Function(String targetId) isCredentialOptIn,
  required Future<bool> Function(String targetId) isInstallOptIn,
  required Future<String?> Function(String targetId, String cliValue)
      cliPathOverride,
  required LocalCredentialsLoader loadLocalCredentials,
  RemoteResourceLinker? linkResources,
  RemoteRelayProvisioner? provisionRelay,
  RemoteInstallAction Function(CliTool cli, SshCommandRunner run)?
      installActionBuilder,
}) {
  final installer =
      RemoteCliInstaller(locator: RemoteCliLocator(registry: registry));
  final appData = RemoteAppDataMaterializer(
    loadLocalCredentials: loadLocalCredentials,
    linkResources: linkResources,
    provisionRelay: provisionRelay,
  );

  return RemoteMemberPreflightCoordinator(
    homeTarget: homeTarget,
    isCredentialOptIn: isCredentialOptIn,
    preflight: RemotePreflightService(
      connect: contextForTarget,
      ensureCli: ({required target, required cli}) async {
        final profile = profileById(target.sshProfileId ?? '');
        if (profile == null) {
          throw StateError(
            'No SSH profile for off-home target "${target.id}".',
          );
        }
        // on-device: real SSH exec over the work machine transport.
        final client = await sshClientFactory.clientFor(profile);
        final run = RemoteCliLocator.runnerForClient(client);
        return installer.ensure(
          cli: cli,
          run: run,
          // B3: per-target auto-install opt-in (default off → locate / manual
          // path only). The install execution itself is on-device.
          optIn: await isInstallOptIn(target.id),
          supportsInstaller:
              registry.capability<InstallerCapability>(cli)?.supportsInstaller ??
                  false,
          install: installActionBuilder?.call(cli, run),
          manualPathOverride:
              await cliPathOverride(target.id, cli.value) ?? '',
        );
      },
      materialize: ({
        required target,
        required workContext,
        required cli,
        required workspaceId,
        required optInCredentials,
      }) async {
        final home = homeContext();
        // on-device: reads home fs, writes the work machine fs (SFTP), links
        // skills/plugins + relay, and (opt-in) pushes credentials.
        await appData.materialize(
          homeFs: home.fs,
          homeRoot: home.appDataRoot,
          workFs: workContext.fs,
          machineRoot: workContext.appDataRoot,
          cli: cli,
          workspaceId: workspaceId,
          optInCredentials: optInCredentials,
        );
      },
      // Bus binding handled by the per-tab RemoteBusBindingResolver.
      bindBus: ({required target, required cli, required memberId}) async => null,
    ),
  );
}
