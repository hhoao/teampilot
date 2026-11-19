import '../../models/connection/device_connection.dart';
import '../../models/connection/machine_id.dart';
import '../../models/connection/ssh_plan.dart';
import '../../models/ssh_profile.dart';
import '../../models/ssh_reachability.dart';

/// Projection of a device connection into the runtime view the app still
/// speaks. The address comes from [DeviceConnection.primaryEndpoint]; nothing
/// else in the app may invent one.
SshProfile profileFromConnection(DeviceConnection connection) {
  final endpoint = connection.primaryEndpoint;
  return SshProfile(
    id: connection.machineId.value,
    name: connection.displayName,
    host: endpoint.host,
    port: endpoint.port,
    username: connection.plan.username,
    authType: connection.plan.authType,
    createdAt: connection.updatedAt,
    updatedAt: connection.updatedAt,
    lastHome: connection.paths?.home,
    lastAppDataRoot: connection.paths?.appDataRoot,
    endpoints: connection.plan.endpoints,
    hostKeyFingerprints: connection.plan.hostKeyFingerprints,
    pairedDesktopId: connection.pairedDesktopId,
    relayUrl: connection.plan.relayUrl,
    lastGoodKind: connection.preferredKind,
    embeddedTarget: connection.plan.embeddedTarget,
    vaultEntryId: connection.plan.credentialRef,
  );
}

/// Write path from the runtime view back into a device connection.
///
/// `host`/`port` are the address of the endpoint selected by
/// [SshProfile.lastGoodKind] (or the first endpoint when no preference is
/// known). Writing them therefore edits exactly one endpoint — it never
/// replaces the whole address set, so a manual address fix keeps the paired
/// LAN/extra/relay plan intact.
DeviceConnection connectionFromProfile(
  SshProfile profile, {
  DeviceConnection? previous,
  required int updatedAt,
}) {
  final kind = profile.lastGoodKind ?? SshEndpointKind.lan;
  final base = profile.endpoints.isNotEmpty
      ? profile.endpoints
      : (previous?.plan.endpoints ?? const <SshReachabilityEndpoint>[]);
  // A relay win is not an address: the tunnel decides where traffic goes, and
  // today's profile keeps its stored host/port. Adding or rewriting a
  // relay-kind endpoint here would change the generation (and retire a healthy
  // lease) every time the relay wins.
  final endpoints = kind == SshEndpointKind.relay
      ? (base.isNotEmpty
            ? base
            : [
                SshReachabilityEndpoint(
                  kind: SshEndpointKind.lan,
                  host: profile.host,
                  port: profile.port,
                ),
              ])
      : _withAddress(
          base,
          kind: kind,
          host: profile.host,
          port: profile.port,
        );
  final paths = _paths(profile);
  return DeviceConnection(
    machineId: MachineId(profile.id),
    displayName: profile.name,
    plan: SshPlan(
      machineId: MachineId(profile.id),
      username: profile.username,
      authType: profile.authType,
      endpoints: endpoints,
      relayUrl: profile.relayUrl,
      hostKeyFingerprints: profile.hostKeyFingerprints,
      embeddedTarget: profile.embeddedTarget,
      credentialRef: profile.vaultEntryId,
    ),
    preferredKind: profile.lastGoodKind,
    paths: paths,
    pairedDesktopId: profile.pairedDesktopId,
    updatedAt: updatedAt,
  );
}

List<SshReachabilityEndpoint> _withAddress(
  List<SshReachabilityEndpoint> endpoints, {
  required SshEndpointKind kind,
  required String host,
  required int port,
}) {
  final replaced = <SshReachabilityEndpoint>[];
  var matched = false;
  for (final endpoint in endpoints) {
    if (!matched && endpoint.kind == kind) {
      matched = true;
      replaced.add(
        SshReachabilityEndpoint(kind: kind, host: host, port: port),
      );
      continue;
    }
    if (endpoint.host == host && endpoint.port == port) {
      // The address is already in the plan under another kind; keep one entry.
      matched = true;
      continue;
    }
    replaced.add(endpoint);
  }
  if (!matched) {
    replaced.insert(
      0,
      SshReachabilityEndpoint(kind: kind, host: host, port: port),
    );
  }
  return replaced;
}

HomePathCache? _paths(SshProfile profile) {
  final home = profile.lastHome?.trim() ?? '';
  final appDataRoot = profile.lastAppDataRoot?.trim() ?? '';
  if (home.isEmpty || appDataRoot.isEmpty) return null;
  return HomePathCache(home: home, appDataRoot: appDataRoot);
}


/// The connection identity this profile implies: the plan's content generation.
///
/// Callers that still hold a projected profile use this to key a pooled
/// connection or a lease. Anything outside the dial plan (display name, path
/// cache, last-good preference) maps to the same value, so it can never
/// invalidate a live connection.
int planGenerationOf(SshProfile profile) =>
    connectionFromProfile(profile, updatedAt: 0).generation;
