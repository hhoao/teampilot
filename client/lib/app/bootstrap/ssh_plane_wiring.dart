import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_known_host_repository.dart';
import '../../services/connect/paired_relay_tunnel_registry.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/ssh/ssh_connection_events.dart';
import '../../services/ssh/ssh_connection_gate.dart';
import '../../services/ssh/worker/ssh_profile_worker_manager.dart';
import '../../services/ssh/worker/ssh_worker_auth_bridge.dart';
import '../../services/ssh/worker/ssh_worker_entry.dart';
import '../../services/ssh/worker/ssh_worker_metrics.dart';
import '../../services/vault/credential_capture.dart';
import '../../services/vault/vault_access.dart';
import '../../utils/logging/logger.dart';
import '../../widgets/ssh/ssh_host_key_prompt_dialog.dart';

/// The device-local SSH transport stack: the paired relay tunnel registry,
/// known-host storage, connection events/gate, the worker-backed
/// [SshClientFactory], and the shared recovery waiter.
typedef SshPlaneWiring = ({
  SshKnownHostRepository sshKnownHosts,
  SshConnectionEvents sshConnectionEvents,
  SshClientFactory sshClientFactory,
  SshConnectionGate connectivityGate,
  PairedRelayTunnelRegistry pairedRelayTunnels,
  Future<bool> Function(Object error) waitForSshProfileRecovery,
});

/// Builds the SSH transport plane. Secrets stay on the device vault via
/// [sshCredentialStore] and [vaultAccess]; only the profile catalog follows
/// the home plane, so this runs before the home-plane identity is resolved.
SshPlaneWiring wireSshTransport({
  required SshCredentialStore sshCredentialStore,
  required SharedPreferences preferences,
  required VaultAccess vaultAccess,
  required VaultCredentialCapture vaultCredentialCapture,
}) {
  // Relay tunnels for paired (QR) SSH profiles: while a tunnel lives, every
  // dial for that profile rides the loopback port instead of the stored host.
  final pairedRelayTunnels = PairedRelayTunnelRegistry(
    credentialStore: sshCredentialStore,
    vault: vaultAccess,
  );
  final sshKnownHostRepo = SharedPrefsSshKnownHostRepository(preferences);
  final sshConnectionEvents = SshConnectionEvents();
  // Shared home-plane catalog rows cannot carry a vault reference; the device
  // vault entry is owned by the profile id instead. Resolve it at connect time
  // so a row created on the plane still finds the secret this device saved.
  // Without this, "test connection" (which resolves the owner entry in the
  // editor) succeeds while the durable connect gets an empty password.
  Future<String?> sshVaultEntryIdFor(String profileId) async {
    try {
      await vaultAccess.tryAutoUnlock();
      final entry = await vaultCredentialCapture.findOwner(
        vaultOwnerKindSshProfile,
        profileId,
      );
      final entryId = (entry?.id ?? '').trim();
      return entryId.isEmpty ? null : entryId;
    } on Object {
      return null;
    }
  }

  final sshWorkerAuthBridge = SshWorkerAuthBridge(
    credentialStore: sshCredentialStore,
    knownHostRepository: sshKnownHostRepo,
    onHostKeyPrompt: showSshHostKeyPrompt,
    dialTargetResolver: (profile) => pairedRelayTunnels.targetFor(profile.id),
    vault: (entryId, field) => vaultAccess.functionalField(entryId, field),
    vaultEntryIdFor: sshVaultEntryIdFor,
  );
  const sshWorkerCaptureMode = String.fromEnvironment(
    'SSH_WORKER_CAPTURE_MODE',
    defaultValue: 'worker',
  );
  final sshWorkerMetrics =
      bool.fromEnvironment('SSH_WORKER_METRICS', defaultValue: false)
      ? SshWorkerMetrics(enabled: true, logDiagnostic: appLogger.i)
      : null;
  final sshWorkerLauncher = sshWorkerCaptureMode == 'direct'
      ? DirectSshWorkerLauncher()
      : const IsolateSshWorkerLauncher();
  final sshProfileWorkerManager = SshProfileWorkerManager(
    launcher: sshWorkerLauncher,
    authChallengeHandlerFor: sshWorkerAuthBridge.handlerFor,
    metrics: sshWorkerMetrics,
  );
  // One app-level gate, owned by the connectivity supervisor. The pure pool
  // only receives its read-only `beforeIo` guard; every state write goes
  // through the supervisor (or its owned coordinator).
  final sshConnectivityGate = SshConnectionGate();
  final sshClientFactory = SshClientFactory(
    credentialStore: sshCredentialStore,
    knownHostRepository: sshKnownHostRepo,
    events: sshConnectionEvents,
    onHostKeyPrompt: showSshHostKeyPrompt,
    dialTargetResolver: (profile) => pairedRelayTunnels.targetFor(profile.id),
    vaultCredentials: (entryId, field) =>
        vaultAccess.functionalField(entryId, field),
    vaultEntryIdFor: sshVaultEntryIdFor,
    workerAuthBridge: sshWorkerAuthBridge,
    workerManager: sshProfileWorkerManager,
    ioGuard: sshConnectivityGate.beforeIo,
  );

  /// Waits for the single connection driver to bring [SshProfileDownException]
  /// profiles back up. Consumers use this instead of polling with their own
  /// backoff.
  Future<bool> waitForSshProfileRecovery(Object error) async {
    if (error is! SshProfileDownException) return false;
    await sshConnectivityGate.waitUntilUp(error.profileId);
    return true;
  }

  return (
    sshKnownHosts: sshKnownHostRepo,
    sshConnectionEvents: sshConnectionEvents,
    sshClientFactory: sshClientFactory,
    connectivityGate: sshConnectivityGate,
    pairedRelayTunnels: pairedRelayTunnels,
    waitForSshProfileRecovery: waitForSshProfileRecovery,
  );
}
