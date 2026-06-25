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
import 'remote_preflight_cli_install.dart';
import 'remote_preflight_service.dart';

/// Caches a resolved remote CLI path into `targets.json` when it differs from
/// the stored per-target override — mirrors local install →
/// `SessionPreferencesCubit.setCliExecutablePathFor`.
Future<void> rememberRemoteCliPathIfNeeded({
  required String targetId,
  required CliTool cli,
  required String resolvedPath,
  required Future<String?> Function(String targetId, String cliValue)
      readCliPathOverride,
  required Future<void> Function(String targetId, String cliValue, String path)
      writeCliPathOverride,
}) async {
  final trimmed = resolvedPath.trim();
  if (trimmed.isEmpty) return;
  final stored = (await readCliPathOverride(targetId, cli.value) ?? '').trim();
  if (trimmed == stored) return;
  await writeCliPathOverride(targetId, cli.value, trimmed);
}

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
  required Future<void> Function(String targetId, String cliValue, String path)
      setCliPathOverride,
  required LocalCredentialsLoader loadLocalCredentials,
  RemoteResourceLinker? linkResources,
  RemoteRelayProvisioner? provisionRelay,
  RemoteInstallAction Function(CliTool cli, SshProfile profile, SshCommandRunner run)?
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
      ensureCli: ({
        required target,
        required cli,
        onCliProgress,
      }) async {
        final profile = profileById(target.sshProfileId ?? '');
        if (profile == null) {
          throw StateError(
            'No SSH profile for off-home target "${target.id}".',
          );
        }
        // on-device: real SSH exec over the work machine transport.
        final client = await sshClientFactory.clientFor(profile);
        final run = RemoteCliLocator.runnerForClient(client);
        final storedPath =
            (await cliPathOverride(target.id, cli.value) ?? '').trim();
        final path = await installer.ensure(
          cli: cli,
          run: run,
          // B3: per-target auto-install opt-out (default on → locate then install
          // over SSH when missing). The install execution itself is on-device.
          optIn: await isInstallOptIn(target.id),
          supportsInstaller:
              registry.capability<InstallerCapability>(cli)?.supportsInstaller ??
                  false,
          install: installActionBuilder?.call(cli, profile, run) ??
              buildRemotePreflightCliInstall(
                registry: registry,
                profile: profile,
                cli: cli,
              ),
          onProgress: onCliProgress,
          manualPathOverride: storedPath,
        );
        await rememberRemoteCliPathIfNeeded(
          targetId: target.id,
          cli: cli,
          resolvedPath: path,
          readCliPathOverride: cliPathOverride,
          writeCliPathOverride: setCliPathOverride,
        );
        return path;
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
