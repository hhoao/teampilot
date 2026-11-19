import 'package:teampilot/models/connection/device_connection.dart';
import 'package:teampilot/models/connection/machine_id.dart';
import 'package:teampilot/models/connection/ssh_plan.dart';
import 'package:teampilot/models/ssh_auth_type.dart';
import 'package:teampilot/models/ssh_reachability.dart';

/// A minimal, fully-addressed connection for tests.
DeviceConnection deviceConnection({
  String machineId = 'm1',
  String displayName = 'dev',
  String username = 'u',
  SshAuthType authType = SshAuthType.password,
  List<SshReachabilityEndpoint>? endpoints,
  SshEndpointKind? preferredKind,
  String? credentialRef,
  HomePathCache? paths,
  String? pairedDesktopId,
  bool embeddedTarget = false,
  String? relayUrl,
  List<String> fingerprints = const [],
  int updatedAt = 1,
}) {
  return DeviceConnection(
    machineId: MachineId(machineId),
    displayName: displayName,
    plan: SshPlan(
      machineId: MachineId(machineId),
      username: username,
      authType: authType,
      endpoints:
          endpoints ??
          const [
            SshReachabilityEndpoint(
              kind: SshEndpointKind.lan,
              host: 'h',
              port: 22,
            ),
          ],
      credentialRef: credentialRef,
      hostKeyFingerprints: fingerprints,
      embeddedTarget: embeddedTarget,
      relayUrl: relayUrl,
    ),
    preferredKind: preferredKind,
    paths: paths,
    pairedDesktopId: pairedDesktopId,
    updatedAt: updatedAt,
  );
}
