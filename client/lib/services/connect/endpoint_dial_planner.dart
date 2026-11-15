import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../../models/ssh_profile.dart';
import '../../models/ssh_reachability.dart';
import '../ssh/ssh_connection_failure.dart';

/// Host-key rejection while dialing a paired endpoint.
///
/// Unlike a network failure this aborts the whole connect attempt: the offer
/// pinned these fingerprints, so no other endpoint may be trusted instead.
class SshHostKeyMismatch implements Exception {
  const SshHostKeyMismatch(this.endpoint);

  final SshReachabilityEndpoint endpoint;

  @override
  String toString() =>
      'SshHostKeyMismatch(${endpoint.kind.name} '
      '${endpoint.host}:${endpoint.port})';
}

/// Dial candidates for a paired profile in try order: the kind of the last
/// successful connect first, then lan → extra → relay, preserving offer order
/// within each kind. [ConnectPolicy.lanOnly] keeps lan candidates only.
///
/// A paired profile has [SshProfile.host] / [SshProfile.port] rewritten to the
/// last winning endpoint, so dialing a different kind first changes the
/// hostIdentifier mid-connect: the storage pool treats that as a profile
/// invalidation and tears down the live lease (and, off-LAN, burns the dial
/// budget on a dead LAN address).
List<SshReachabilityEndpoint> planEndpointDials(
  SshProfile profile, {
  ConnectPolicy policy = ConnectPolicy.automatic,
}) {
  final byKind = {
    for (final kind in SshEndpointKind.values)
      kind: <SshReachabilityEndpoint>[],
  };
  for (final endpoint in profile.endpoints) {
    if (policy == ConnectPolicy.lanOnly &&
        endpoint.kind != SshEndpointKind.lan) {
      continue;
    }
    byKind[endpoint.kind]!.add(endpoint);
  }
  final lastGood = profile.lastGoodKind;
  return [
    if (lastGood != null) ...byKind[lastGood]!,
    for (final kind in SshEndpointKind.values)
      if (kind != lastGood) ...byKind[kind]!,
  ];
}

/// The stored-profile view after [endpoint] won a paired connect.
///
/// Relay wins never rewrite host/port: the SSH traffic rode a loopback
/// tunnel that must not leak into the persisted profile.
SshProfile withLastGoodEndpoint(
  SshProfile profile,
  SshReachabilityEndpoint endpoint,
) {
  return switch (endpoint.kind) {
    SshEndpointKind.relay => profile.copyWith(
      lastGoodKind: SshEndpointKind.relay,
    ),
    _ => profile.copyWith(
      host: endpoint.host,
      port: endpoint.port,
      lastGoodKind: endpoint.kind,
    ),
  };
}

typedef SshPairedProfileSaver = Future<void> Function(SshProfile updated);

/// Opens the phone-side relay tunnel for [profile]; resolves to the loopback
/// target dartssh2 should dial for relay traffic.
typedef SshRelayTunnelOpener =
    Future<({InternetAddress address, int port})> Function(
      SshProfile profile,
      SshReachabilityEndpoint endpoint,
    );

/// Tries a paired profile's endpoints in planner order with short
/// per-endpoint timeouts and persists last-good state on the first success.
///
/// Network failures (and timeouts) fall through to the next candidate; a
/// host-key mismatch aborts the whole attempt via [SshHostKeyMismatch].
/// When [openRelayTunnel] is null, relay candidates are skipped.
class PairedConnectAttempt {
  PairedConnectAttempt({
    required this.saveLastGood,
    this.openRelayTunnel,
    this.policy = ConnectPolicy.automatic,
    this.perEndpointTimeout = const Duration(seconds: 5),
  });

  final SshPairedProfileSaver saveLastGood;
  final SshRelayTunnelOpener? openRelayTunnel;
  final ConnectPolicy policy;
  final Duration perEndpointTimeout;

  Future<SshReachabilityEndpoint> connectFirst({
    required SshProfile profile,
    required Future<void> Function(SshReachabilityEndpoint endpoint) dial,
    Duration? perEndpointTimeout,
  }) async {
    final timeout = perEndpointTimeout ?? this.perEndpointTimeout;
    Object? lastFailure;
    for (final candidate in planEndpointDials(profile, policy: policy)) {
      if (candidate.kind == SshEndpointKind.relay && openRelayTunnel == null) {
        continue;
      }
      try {
        await dial(candidate).timeout(timeout);
      } on SshHostKeyMismatch {
        rethrow;
      } on Object catch (error) {
        if (_isHostKeyRejection(error)) {
          throw SshHostKeyMismatch(candidate);
        }
        lastFailure ??= error;
        continue;
      }
      await saveLastGood(withLastGoodEndpoint(profile, candidate));
      return candidate;
    }
    throw lastFailure ??
        StateError('no dialable endpoints for profile ${profile.id}');
  }

  bool _isHostKeyRejection(Object error) =>
      sshConnectionFailureCause(error) is SSHHostkeyError;
}
