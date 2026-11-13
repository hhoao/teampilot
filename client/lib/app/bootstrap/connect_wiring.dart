import 'dart:io';

import '../../cubits/connect_cubit.dart';
import '../../services/connect/authorized_keys_file.dart';
import '../../services/connect/connect_agent.dart';
import '../../services/connect/connect_backend_host.dart';
import '../../services/connect/connect_settings_store.dart';
import '../../services/connect/connect_ssh_backend.dart';
import '../../services/connect/embedded_ssh_server.dart';
import '../../services/connect/paired_device_store.dart';
import '../../services/connect/sshd_presence.dart';
import '../../services/connect/system_sshd_backend.dart';
import '../../services/io/local_filesystem.dart';
import '../../services/storage/app_paths.dart';
import '../../utils/logging/logger.dart';

/// The shell's Connect backend stack.
///
/// Every member is `null` on Android, which has no Connect host.
typedef ConnectWiring = ({
  ConnectCubit? connectCubit,
  ConnectSshBackend? embeddedSshServer,
  ConnectSshBackend? systemSshdBackend,
  PairedDeviceStore? connectDeviceStore,
});

/// Builds the desktop Connect stack behind the device-local app data root:
/// embedded sshd, the optional Linux/macOS system OpenSSH backend, the shared
/// paired device store, the app-lifetime pairing agent (and its relay
/// registration) and the [ConnectCubit] that drives the Connect UI.
///
/// Android returns an all-null [ConnectWiring] without touching the
/// filesystem, because there is no Connect host there.
Future<ConnectWiring> wireConnectBackend({
  required String nativeAppDataPath,
}) async {
  ConnectCubit? connectCubit;
  ConnectSshBackend? embeddedSshServer;
  ConnectSshBackend? systemSshdBackend;
  PairedDeviceStore? connectDeviceStore;
  if (!Platform.isAndroid) {
    final localFs = LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
    );
    final nativeHome =
        (Platform.environment['HOME'] ??
                Platform.environment['USERPROFILE'] ??
                '')
            .trim();
    if (nativeHome.isEmpty) {
      throw StateError('Could not resolve the local user home for Connect');
    }
    final username =
        (Platform.environment['USER'] ??
                Platform.environment['USERNAME'] ??
                localFs.pathContext.basename(nativeHome))
            .trim();
    final settingsStore = ConnectSettingsStore(
      fs: localFs,
      appDataRoot: nativeAppDataPath,
    );
    final settings = await settingsStore.load();
    final pairedDeviceStore = PairedDeviceStore(
      fs: localFs,
      appDataRoot: nativeAppDataPath,
    );
    connectDeviceStore = pairedDeviceStore;
    final server = EmbeddedSshServer(
      fs: localFs,
      appDataRoot: nativeAppDataPath,
      deviceStore: pairedDeviceStore,
      username: username,
      homePath: nativeHome,
    );
    final systemSshdSelectable = Platform.isLinux || Platform.isMacOS;
    final systemBackend = systemSshdSelectable
        ? SystemSshdBackend(
            presence: SshdPresence(
              probe: loopbackSshdProbe(),
              scan: sshKeyScanRunner(
                run: (exe, args) async {
                  final result = await Process.run(exe, args);
                  return (
                    exitCode: result.exitCode,
                    stdout: result.stdout.toString(),
                    stderr: result.stderr.toString(),
                  );
                },
              ),
            ),
            authorizedKeys: AuthorizedKeysFile(
              fs: localFs,
              homePath: nativeHome,
              chmod600: (path) async {
                await Process.run('chmod', ['600', path]);
              },
            ),
          )
        : null;
    final backendHost = ConnectBackendHost(
      embedded: server,
      system: systemBackend,
      settings: settingsStore,
      systemSshdSelectable: systemSshdSelectable,
    );
    try {
      await backendHost.startSelected();
    } on Object catch (error, stackTrace) {
      // Non-blocking: the app continues; the Connect UI shows the failed
      // state with a retry affordance. Broad on purpose — anything from a
      // typed [EmbeddedSshServerStartException] (bind conflicts) to a
      // host-key persistence failure must not crash app boot.
      appLogger.e(
        '[connect] ssh backend failed to start',
        error: error,
        stackTrace: stackTrace,
      );
    }
    embeddedSshServer = server;
    systemSshdBackend = systemBackend;
    final connectAgent = ConnectAgent.production(
      sshBackend: backendHost.current,
      fs: localFs,
      extraEndpoints: settings.extraEndpoints,
      deviceStore: pairedDeviceStore,
    );
    // App-lifetime relay registration: keeps off-LAN SSH reachable via
    // device grants even when no QR is on screen.
    final relayUrl = settings.relayUrl.trim();
    if (relayUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(relayUrl);
        if (uri.scheme == 'ws' || uri.scheme == 'wss') {
          await connectAgent.enableRelay(
            appDataRoot: nativeAppDataPath,
            registration: _relayRegistrationFor(uri),
          );
        }
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[connect-relay] startup registration failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    connectCubit = ConnectCubit(
      agent: ConnectAgentController.fromAgent(connectAgent),
      backends: backendHost,
      systemSshdHint: Platform.isMacOS
          ? ConnectSystemSshdHint.macos
          : (Platform.isLinux
                ? ConnectSystemSshdHint.linux
                : ConnectSystemSshdHint.none),
      deviceStore: pairedDeviceStore,
      settingsStore: settingsStore,
      listNetworkAddresses: () async {
        final interfaces = await NetworkInterface.list(includeLoopback: true);
        return [
          for (final interface in interfaces)
            for (final address in interface.addresses)
              ConnectNetworkAddress(
                name: interface.name,
                address: address.address,
                isLoopback: address.isLoopback,
                isIpv4: address.type == InternetAddressType.IPv4,
              ),
        ];
      },
      username: username,
      displayName: Platform.localHostname,
      appDataRoot: nativeAppDataPath,
    );
  }
  return (
    connectCubit: connectCubit,
    embeddedSshServer: embeddedSshServer,
    systemSshdBackend: systemSshdBackend,
    connectDeviceStore: connectDeviceStore,
  );
}

ConnectRelayRegistration _relayRegistrationFor(Uri uri) {
  return ConnectRelayRegistration(
    url: uri.toString(),
    endpointHost: uri.host,
    endpointPort: uri.port == 0 ? (uri.scheme == 'wss' ? 443 : 80) : uri.port,
  );
}
