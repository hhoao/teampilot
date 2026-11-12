import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ssh_profile.dart';
import '../models/ssh_reachability.dart';
import '../services/connect/endpoint_dial_planner.dart';
import '../services/connect/paired_relay_tunnel_registry.dart';
import '../services/ssh/remote_target_sync.dart';
import '../services/ssh/ssh_client_factory.dart';
import '../services/ssh/ssh_connection_failure.dart';
import '../services/ssh/ssh_home_connectivity_state.dart';
import '../services/ssh/ssh_profile_connection_coordinator.dart';
import '../utils/logging/logger.dart';

enum SshHostUiStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
  authFailed,
}

@immutable
class SshHostConnectionVm {
  const SshHostConnectionVm({
    required this.profileId,
    required this.label,
    required this.host,
    required this.status,
    this.errorDetail,
  });

  final String profileId;
  final String label;
  final String host;
  final SshHostUiStatus status;
  final String? errorDetail;
}

enum SshHostsOverallStatus { connected, partial, connecting, disconnected }

@immutable
class SshConnectionState {
  const SshConnectionState({
    this.hostsById = const {},
    this.profileOrder = const [],
  });

  final Map<String, SshHostConnectionVm> hostsById;
  final List<String> profileOrder;

  bool get isEmpty => profileOrder.isEmpty;

  int get connectedCount => hostsById.values
      .where((h) => h.status == SshHostUiStatus.connected)
      .length;

  SshHostsOverallStatus get overallStatus {
    if (profileOrder.isEmpty) return SshHostsOverallStatus.disconnected;

    final hosts = profileOrder
        .map((id) => hostsById[id])
        .whereType<SshHostConnectionVm>()
        .toList(growable: false);
    if (hosts.isEmpty) return SshHostsOverallStatus.disconnected;

    final everyConnected = hosts.every(
      (h) => h.status == SshHostUiStatus.connected,
    );
    if (everyConnected) return SshHostsOverallStatus.connected;

    final anyConnecting = hosts.any(
      (h) =>
          h.status == SshHostUiStatus.connecting ||
          h.status == SshHostUiStatus.reconnecting,
    );
    if (anyConnecting) return SshHostsOverallStatus.connecting;

    final anyConnected = hosts.any(
      (h) => h.status == SshHostUiStatus.connected,
    );
    if (anyConnected) return SshHostsOverallStatus.partial;

    return SshHostsOverallStatus.disconnected;
  }

  List<SshHostConnectionVm> get connectedHosts {
    final hosts = hostsById.values
        .where((h) => h.status == SshHostUiStatus.connected)
        .toList(growable: false);
    return List<SshHostConnectionVm>.unmodifiable(
      hosts..sort((a, b) => a.label.compareTo(b.label)),
    );
  }

  List<SshHostConnectionVm> get inactiveHosts {
    final hosts = hostsById.values
        .where((h) => h.status != SshHostUiStatus.connected)
        .toList(growable: false);
    return List<SshHostConnectionVm>.unmodifiable(
      hosts..sort((a, b) => a.label.compareTo(b.label)),
    );
  }
}

/// Projection of [SshConnectivitySource] onto the durable SSH hosts UI.
///
/// The supervisor is the single source of truth for connectivity state. This
/// cubit owns only the profile catalog and command plumbing; it publishes
/// command outcomes (connecting / failure) through [publish] and projects
/// [stateFor] into view models. It never keeps an independent connected flag.
class SshConnectionCubit extends Cubit<SshConnectionState> {
  SshConnectionCubit({
    required SshClientFactory factory,
    required SshProfileConnectionCoordinator coordinator,
    required SshConnectivitySource connectivity,
    Future<void> Function(String id)? selectProfileOnConnect,
    PairedConnectAttempt? pairedConnectAttempt,
    PairedRelayTunnelRegistry? relayTunnels,
    RemoteTargetSync? sync,
  }) : _factory = factory,
       _coordinator = coordinator,
       _connectivity = connectivity,
       _selectProfileOnConnect = selectProfileOnConnect,
       _pairedConnectAttempt = pairedConnectAttempt,
       _relayTunnels = relayTunnels,
       _sync = sync,
       super(const SshConnectionState()) {
    _connectivitySub = _connectivity.changes.listen((_) => emit(_buildState()));
  }

  final SshClientFactory _factory;
  final SshProfileConnectionCoordinator _coordinator;
  final SshConnectivitySource _connectivity;
  final Future<void> Function(String id)? _selectProfileOnConnect;
  final PairedConnectAttempt? _pairedConnectAttempt;
  final PairedRelayTunnelRegistry? _relayTunnels;
  final RemoteTargetSync? _sync;

  final Map<String, SshProfile> _profilesById = {};
  StreamSubscription<SshHomeConnectivityState>? _connectivitySub;

  Future<void> syncProfiles(List<SshProfile> profiles) async {
    final nextIds = profiles.map((p) => p.id).toSet();
    final removed = _profilesById.keys
        .where((id) => !nextIds.contains(id))
        .toList(growable: false);

    for (final id in removed) {
      // Always disconnect: cancels reconnect timers + sets latch even when
      // the pool is already cold or a reconnect is in flight.
      await _relayTunnels?.closeFor(id);
      await _coordinator.userDisconnect(id);
      _profilesById.remove(id);
    }

    _profilesById
      ..clear()
      ..addEntries(profiles.map((p) => MapEntry(p.id, p)));

    emit(_buildState());
  }

  /// [switchHome] is the Android Connect side effect (rebind the home plane to
  /// the connected host). The SSH servers page passes false: its connect is
  /// the desktop one — open a connection and keep the current home.
  Future<void> connect(String profileId, {bool switchHome = true}) async {
    final profile = _profilesById[profileId];
    if (profile == null) return;

    _connectivity.publish(
      _connectivity.stateFor(profileId).copyWith(
        phase: SshPhase.connecting,
        attempt: 0,
        storageLive: false,
        clearFailure: true,
        clearErrorDetail: true,
      ),
    );
    emit(_buildState());

    try {
      await _connectProfile(profile);
      if (!_profilesById.containsKey(profileId)) {
        await _coordinator.userDisconnect(profileId);
        return;
      }
      final select = switchHome ? _selectProfileOnConnect : null;
      if (select != null) {
        await select(profileId);
      }
      if (!_profilesById.containsKey(profileId)) {
        await _coordinator.userDisconnect(profileId);
        return;
      }
      // Post-connect target sync runs AFTER select() has rebound the home
      // plane (Android Connect rebinds home onto the SSH host), so the remote
      // SshServerProfile lands on the connected host rather than the previous
      // local/catalog plane. A sync failure must never fail the connection, so
      // it lives in its own try/catch: leave pendingSync untouched and let the
      // next connect retry. sync is optional, so guard the whole block.
      final sync = _sync;
      if (sync != null) {
        try {
          final target = await sync.targets.findById(profileId);
          if (target != null) {
            final server = await sync.servers.findById(target.id);
            if (server == null) {
              // First connect: seed the remote profile from the local target.
              await sync.push(target);
            } else {
              final merged = await sync.pull(target);
              if (merged.pendingSync) await sync.push(merged);
            }
          }
        } on Object {
          appLogger.w(
            '[ssh] profile $profileId target sync failed; '
            'will retry on next connect',
          );
        }
      }
      // A dial that succeeded means a lease is cached: publish `up`, which
      // atomically clears any prior failure (invariant 2 + 3). This works
      // with any SshConnectivitySource, so command-driven tests stay real.
      if (_factory.hasLiveStorageClient(profileId)) {
        _connectivity.publish(SshHomeConnectivityState.up(profileId));
      }
      emit(_buildState());
    } catch (error, stackTrace) {
      if (!_profilesById.containsKey(profileId)) {
        return;
      }
      final cause = sshConnectionFailureCause(error);
      // A paired profile pins the desktop's identity: its host-key
      // fingerprints and, for embedded targets, the embedded port. A host-key
      // rejection against the pins means the desktop re-keyed (upgrade,
      // reset, re-pair); a TCP refusal means the desktop answered but
      // nothing listens on the pinned port (the port was re-picked — an
      // offline desktop would time out instead). Both are repaired only by
      // scanning a new pairing code.
      final stalePairing =
          profile.pairedDesktopId != null &&
          (((error is SshHostKeyMismatch || isSshHostKeyFailure(error)) &&
                  profile.hostKeyFingerprints.isNotEmpty) ||
              (profile.embeddedTarget && isTcpConnectionRefused(error)));
      final authFailed = isSshAuthFailure(error);
      _connectivity.publish(
        _connectivity.stateFor(profileId).copyWith(
          phase: SshPhase.failed,
          failure: authFailed
              ? SshFailureKind.authFailed
              : SshFailureKind.transportError,
          errorDetail: stalePairing
              ? sshPairingStaleDetail
              : error.toString(),
          storageLive: false,
        ),
      );
      appLogger.w(
        '[ssh] profile $profileId connect failed: '
        '${sshConnectionFailureLogMessage(error)}',
        error: cause,
        stackTrace: stackTrace,
      );
      emit(_buildState());
    }
  }

  /// Paired profiles dial their endpoints in planner order (lan → extra →
  /// relay) and keep the winning endpoint; manual profiles connect as before.
  Future<void> _connectProfile(SshProfile profile) async {
    final attempt = _pairedConnectAttempt;
    final tunnels = _relayTunnels;
    if (attempt == null ||
        profile.pairedDesktopId == null ||
        planEndpointDials(profile).isEmpty) {
      await _coordinator.userConnect(profile);
      return;
    }
    final SshReachabilityEndpoint winner;
    try {
      winner = await attempt.connectFirst(
        profile: profile,
        dial: (endpoint) => _dialCandidate(tunnels, profile, endpoint),
      );
    } on Object {
      await tunnels?.closeFor(profile.id);
      rethrow;
    }
    final updated = withLastGoodEndpoint(profile, winner);
    // Keep the UI and the pooled connection on the same host identity.
    if (_profilesById[profile.id]?.id == profile.id) {
      _profilesById[profile.id] = updated;
    }
  }

  Future<void> _dialCandidate(
    PairedRelayTunnelRegistry? tunnels,
    SshProfile profile,
    SshReachabilityEndpoint endpoint,
  ) async {
    if (endpoint.kind == SshEndpointKind.relay && tunnels != null) {
      // Route the pool through the tunnel before dialing: the factory's
      // dial resolver sends every connection for this profile to loopback.
      await tunnels.ensureSshTunnel(profile);
      try {
        return await _coordinator.userConnect(profile);
      } on Object {
        await tunnels.closeFor(profile.id);
        rethrow;
      }
    }
    await tunnels?.closeFor(profile.id);
    await _coordinator.userConnect(withLastGoodEndpoint(profile, endpoint));
  }

  Future<void> disconnect(String profileId) async {
    if (!_profilesById.containsKey(profileId)) return;
    _connectivity.publish(
      _connectivity.stateFor(profileId).copyWith(
        phase: SshPhase.suspended,
        attempt: 0,
        storageLive: false,
      ),
    );
    await _relayTunnels?.closeFor(profileId);
    await _coordinator.userDisconnect(profileId);
    emit(_buildState());
  }

  SshConnectionState _buildState() {
    final order = _profilesById.keys.toList(growable: false);
    final hosts = <String, SshHostConnectionVm>{};
    for (final id in order) {
      final profile = _profilesById[id]!;
      final state = _connectivity.stateFor(id);
      hosts[id] = SshHostConnectionVm(
        profileId: id,
        label: _labelFor(profile),
        host: profile.host,
        status: _project(state),
        errorDetail: state.errorDetail,
      );
    }
    return SshConnectionState(hostsById: hosts, profileOrder: order);
  }

  SshHostUiStatus _project(SshHomeConnectivityState s) => switch (s.phase) {
    SshPhase.connecting => SshHostUiStatus.connecting,
    SshPhase.up || SshPhase.degraded => SshHostUiStatus.connected,
    SshPhase.reconnecting => SshHostUiStatus.reconnecting,
    SshPhase.failed => s.failure == SshFailureKind.authFailed
        ? SshHostUiStatus.authFailed
        : SshHostUiStatus.error,
    SshPhase.idle ||
    SshPhase.unreachable ||
    SshPhase.suspended => SshHostUiStatus.disconnected,
  };

  String _labelFor(SshProfile profile) {
    final name = profile.name.trim();
    return name.isEmpty ? profile.host : name;
  }

  @override
  Future<void> close() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    return super.close();
  }
}
