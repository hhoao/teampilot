import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ssh_profile.dart';
import '../services/remote/remote_connection_monitor.dart';
import '../services/ssh/ssh_client_factory.dart';
import '../services/ssh/ssh_connection_failure.dart';
import '../services/ssh/ssh_profile_connection_coordinator.dart';

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

/// Global UI truth for durable SSH storage-pool connections.
class SshConnectionCubit extends Cubit<SshConnectionState> {
  SshConnectionCubit({
    required SshClientFactory factory,
    required SshProfileConnectionCoordinator coordinator,
    Future<void> Function(String id)? selectProfileOnConnect,
  }) : _factory = factory,
       _coordinator = coordinator,
       _selectProfileOnConnect = selectProfileOnConnect,
       super(const SshConnectionState()) {
    _poolSubscription = _factory.storagePoolChanges.listen(_onPoolChanged);
  }

  final SshClientFactory _factory;
  final SshProfileConnectionCoordinator _coordinator;
  final Future<void> Function(String id)? _selectProfileOnConnect;

  final Map<String, SshProfile> _profilesById = {};
  final Map<String, StreamSubscription<RemoteConnectionState>>
  _monitorSubscriptions = {};
  final Set<String> _connectingIds = {};
  final Map<String, String?> _lastErrorDetail = {};
  final Map<String, SshHostUiStatus> _lastFailureStatus = {};

  StreamSubscription<String>? _poolSubscription;

  void syncProfiles(List<SshProfile> profiles) {
    final nextIds = profiles.map((p) => p.id).toSet();
    final removed = _profilesById.keys
        .where((id) => !nextIds.contains(id))
        .toList(growable: false);

    for (final id in removed) {
      _unsubscribeMonitor(id);
      _profilesById.remove(id);
      _connectingIds.remove(id);
      _lastErrorDetail.remove(id);
      _lastFailureStatus.remove(id);
    }

    _profilesById
      ..clear()
      ..addEntries(profiles.map((p) => MapEntry(p.id, p)));

    for (final profile in profiles) {
      _subscribeMonitor(profile.id);
    }

    emit(_buildState());
  }

  Future<void> connect(String profileId) async {
    final profile = _profilesById[profileId];
    if (profile == null) return;

    _connectingIds.add(profileId);
    _lastErrorDetail.remove(profileId);
    _lastFailureStatus.remove(profileId);
    emit(_buildState());

    try {
      await _coordinator.userConnect(profile);
      _connectingIds.remove(profileId);
      final select = _selectProfileOnConnect;
      if (select != null) {
        await select(profileId);
      }
      emit(_buildState());
    } catch (error) {
      _connectingIds.remove(profileId);
      final cause = sshConnectionFailureCause(error);
      final authFailed =
          cause is SSHAuthFailError || cause is SSHHostkeyError;
      final status = authFailed
          ? SshHostUiStatus.authFailed
          : SshHostUiStatus.error;
      _lastFailureStatus[profileId] = status;
      _lastErrorDetail[profileId] = error.toString();
      emit(_buildState());
    }
  }

  Future<void> disconnect(String profileId) async {
    if (!_profilesById.containsKey(profileId)) return;
    _connectingIds.remove(profileId);
    _lastErrorDetail.remove(profileId);
    _lastFailureStatus.remove(profileId);
    await _coordinator.userDisconnect(profileId);
    emit(_buildState());
  }

  void _onPoolChanged(String profileId) {
    if (!_profilesById.containsKey(profileId)) return;
    if (_factory.hasLiveStorageClient(profileId)) {
      _lastErrorDetail.remove(profileId);
      _lastFailureStatus.remove(profileId);
    }
    emit(_buildState());
  }

  void _onMonitorChanged(String profileId, RemoteConnectionState _) {
    if (!_profilesById.containsKey(profileId)) return;
    emit(_buildState());
  }

  void _subscribeMonitor(String profileId) {
    if (_monitorSubscriptions.containsKey(profileId)) return;
    _monitorSubscriptions[profileId] = _coordinator
        .changesFor(profileId)
        .listen((state) => _onMonitorChanged(profileId, state));
  }

  void _unsubscribeMonitor(String profileId) {
    unawaited(_monitorSubscriptions.remove(profileId)?.cancel());
  }

  SshConnectionState _buildState() {
    final order = _profilesById.keys.toList(growable: false);
    final hosts = <String, SshHostConnectionVm>{};
    for (final id in order) {
      final profile = _profilesById[id]!;
      hosts[id] = SshHostConnectionVm(
        profileId: id,
        label: _labelFor(profile),
        host: profile.host,
        status: _resolveStatus(id),
        errorDetail: _lastErrorDetail[id],
      );
    }
    return SshConnectionState(hostsById: hosts, profileOrder: order);
  }

  SshHostUiStatus _resolveStatus(String profileId) {
    if (_connectingIds.contains(profileId)) {
      return SshHostUiStatus.connecting;
    }

    final live = _factory.hasLiveStorageClient(profileId);
    final monitorStatus = _coordinator.monitorFor(profileId).state.status;

    if (live) {
      if (monitorStatus == RemoteConnectionStatus.reconnecting) {
        return SshHostUiStatus.reconnecting;
      }
      // degraded (and connected) both surface as connected.
      return SshHostUiStatus.connected;
    }

    if (monitorStatus == RemoteConnectionStatus.reconnecting) {
      return SshHostUiStatus.reconnecting;
    }

    final failure = _lastFailureStatus[profileId];
    if (failure != null) return failure;

    return SshHostUiStatus.disconnected;
  }

  String _labelFor(SshProfile profile) {
    final name = profile.name.trim();
    return name.isEmpty ? profile.host : name;
  }

  @override
  Future<void> close() async {
    await _poolSubscription?.cancel();
    _poolSubscription = null;
    for (final id in _monitorSubscriptions.keys.toList(growable: false)) {
      _unsubscribeMonitor(id);
    }
    return super.close();
  }
}
