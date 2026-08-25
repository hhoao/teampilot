import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ssh_reachability.dart';
import '../services/connect/authorized_keys_file.dart';
import '../services/connect/connect_agent.dart';
import '../services/connect/connect_settings_store.dart';
import '../services/connect/ssh_pairing_offer.dart';
import '../services/connect/sshd_presence.dart';

typedef ConnectAgentStartQrSession =
    Future<void> Function({
      required String advertiseAddress,
      required String username,
      required String displayName,
      required String appDataRoot,
    });
typedef ConnectNetworkAddressLookup =
    Future<List<ConnectNetworkAddress>> Function();

class ConnectAgentController {
  const ConnectAgentController({
    required SshPairingOffer? Function() currentOffer,
    required ConnectAgentStartQrSession startQrSession,
    required Future<void> Function() stopQrSession,
    required Future<void> Function() regenerateQr,
  }) : _currentOffer = currentOffer,
       _startQrSession = startQrSession,
       _stopQrSession = stopQrSession,
       _regenerateQr = regenerateQr;

  factory ConnectAgentController.fromAgent(ConnectAgent agent) {
    return ConnectAgentController(
      currentOffer: () => agent.currentOffer,
      startQrSession: agent.startQrSession,
      stopQrSession: agent.stopQrSession,
      regenerateQr: agent.regenerateQr,
    );
  }

  final SshPairingOffer? Function() _currentOffer;
  final ConnectAgentStartQrSession _startQrSession;
  final Future<void> Function() _stopQrSession;
  final Future<void> Function() _regenerateQr;

  SshPairingOffer? get currentOffer => _currentOffer();

  Future<void> startQrSession({
    required String advertiseAddress,
    required String username,
    required String displayName,
    required String appDataRoot,
  }) => _startQrSession(
    advertiseAddress: advertiseAddress,
    username: username,
    displayName: displayName,
    appDataRoot: appDataRoot,
  );

  Future<void> stopQrSession() => _stopQrSession();

  Future<void> regenerateQr() => _regenerateQr();
}

class ConnectNetworkAddress extends Equatable {
  const ConnectNetworkAddress({
    required this.name,
    required this.address,
    required this.isLoopback,
    required this.isIpv4,
  });

  final String name;
  final String address;
  final bool isLoopback;
  final bool isIpv4;

  String get label => name.isEmpty ? address : '$name · $address';

  @override
  List<Object?> get props => [name, address, isLoopback, isIpv4];
}

class ConnectPairedDevice extends Equatable {
  const ConnectPairedDevice({required this.deviceId, required this.name});

  final String deviceId;
  final String name;

  @override
  List<Object?> get props => [deviceId, name];
}

const _initialSshd = SshdPresenceSnapshot(
  listening: false,
  port: 22,
  fingerprints: [],
  enableHint: '',
);

class ConnectState extends Equatable {
  const ConnectState({
    this.sshd = _initialSshd,
    this.offer,
    this.networkAddresses = const [],
    this.selectedAddress,
    this.pairedDevices = const [],
    this.extraEndpoints = const [],
    this.relayUrl = '',
    this.loading = false,
    this.saving = false,
    this.hasError = false,
  });

  final SshdPresenceSnapshot sshd;
  final SshPairingOffer? offer;
  final List<ConnectNetworkAddress> networkAddresses;
  final String? selectedAddress;
  final List<ConnectPairedDevice> pairedDevices;
  final List<SshReachabilityEndpoint> extraEndpoints;
  final String relayUrl;
  final bool loading;
  final bool saving;
  final bool hasError;

  bool get canPair => sshd.listening && sshd.fingerprints.isNotEmpty;

  ConnectState copyWith({
    SshdPresenceSnapshot? sshd,
    SshPairingOffer? offer,
    bool clearOffer = false,
    List<ConnectNetworkAddress>? networkAddresses,
    String? selectedAddress,
    bool clearSelectedAddress = false,
    List<ConnectPairedDevice>? pairedDevices,
    List<SshReachabilityEndpoint>? extraEndpoints,
    String? relayUrl,
    bool? loading,
    bool? saving,
    bool? hasError,
  }) {
    return ConnectState(
      sshd: sshd ?? this.sshd,
      offer: clearOffer ? null : offer ?? this.offer,
      networkAddresses: networkAddresses ?? this.networkAddresses,
      selectedAddress: clearSelectedAddress
          ? null
          : selectedAddress ?? this.selectedAddress,
      pairedDevices: pairedDevices ?? this.pairedDevices,
      extraEndpoints: extraEndpoints ?? this.extraEndpoints,
      relayUrl: relayUrl ?? this.relayUrl,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      hasError: hasError ?? this.hasError,
    );
  }

  @override
  List<Object?> get props => [
    sshd.listening,
    sshd.port,
    sshd.fingerprints,
    sshd.enableHint,
    offer?.encode(),
    networkAddresses,
    selectedAddress,
    pairedDevices,
    extraEndpoints,
    relayUrl,
    loading,
    saving,
    hasError,
  ];
}

class ConnectCubit extends Cubit<ConnectState> {
  ConnectCubit({
    required ConnectAgentController agent,
    required SshdPresenceProbe probeSshd,
    required AuthorizedKeysFile authorizedKeys,
    required ConnectSettingsStore settingsStore,
    required ConnectNetworkAddressLookup listNetworkAddresses,
    required String username,
    required String displayName,
    required String appDataRoot,
  }) : _agent = agent,
       _probeSshd = probeSshd,
       _authorizedKeys = authorizedKeys,
       _settingsStore = settingsStore,
       _listNetworkAddresses = listNetworkAddresses,
       _username = username,
       _displayName = displayName,
       _appDataRoot = appDataRoot,
       super(const ConnectState());

  final ConnectAgentController _agent;
  final SshdPresenceProbe _probeSshd;
  final AuthorizedKeysFile _authorizedKeys;
  final ConnectSettingsStore _settingsStore;
  final ConnectNetworkAddressLookup _listNetworkAddresses;
  final String _username;
  final String _displayName;
  final String _appDataRoot;

  bool _qrSessionVisible = false;
  int _operationId = 0;

  Future<void> openQrSession() async {
    if (_qrSessionVisible) return;
    _qrSessionVisible = true;
    await refresh();
  }

  Future<void> refresh() async {
    if (!_qrSessionVisible) return;
    final operationId = ++_operationId;
    emit(state.copyWith(loading: true, hasError: false, clearOffer: true));
    try {
      final sshd = await _probeSshd();
      final addresses = (await _listNetworkAddresses())
          .where((address) => address.isIpv4 && !address.isLoopback)
          .toList(growable: false);
      final settings = await _settingsStore.load();
      final devices = await _loadPairedDevices();
      if (!_isCurrent(operationId)) return;

      final selectedAddress =
          addresses.any((address) => address.address == state.selectedAddress)
          ? state.selectedAddress
          : addresses.firstOrNull?.address;
      emit(
        state.copyWith(
          sshd: sshd,
          networkAddresses: addresses,
          selectedAddress: selectedAddress,
          clearSelectedAddress: selectedAddress == null,
          pairedDevices: devices,
          extraEndpoints: settings.extraEndpoints,
          relayUrl: settings.relayUrl,
          loading: true,
          hasError: false,
          clearOffer: true,
        ),
      );

      if (!state.canPair || selectedAddress == null) {
        await _agent.stopQrSession();
        if (_isCurrent(operationId)) {
          emit(state.copyWith(loading: false, clearOffer: true));
        }
        return;
      }

      await _startFor(selectedAddress);
      if (!_isCurrent(operationId)) return;
      final offer = _agent.currentOffer;
      emit(
        state.copyWith(offer: offer, clearOffer: offer == null, loading: false),
      );
    } on Object {
      await _stopQuietly();
      if (_isCurrent(operationId)) {
        emit(state.copyWith(loading: false, hasError: true, clearOffer: true));
      }
    }
  }

  Future<void> selectAddress(String address) async {
    if (!_qrSessionVisible) return;
    if (!state.networkAddresses.any((item) => item.address == address)) return;
    emit(
      state.copyWith(
        selectedAddress: address,
        loading: true,
        hasError: false,
        clearOffer: true,
      ),
    );
    final operationId = ++_operationId;
    try {
      await _startFor(address);
      if (!_isCurrent(operationId)) return;
      final offer = _agent.currentOffer;
      emit(
        state.copyWith(offer: offer, clearOffer: offer == null, loading: false),
      );
    } on Object {
      await _stopQuietly();
      if (_isCurrent(operationId)) {
        emit(state.copyWith(loading: false, hasError: true, clearOffer: true));
      }
    }
  }

  Future<void> regenerateQr() async {
    if (!_qrSessionVisible || state.offer == null) return;
    emit(state.copyWith(loading: true, hasError: false));
    try {
      await _agent.regenerateQr();
      if (!_qrSessionVisible || isClosed) return;
      final offer = _agent.currentOffer;
      emit(
        state.copyWith(offer: offer, clearOffer: offer == null, loading: false),
      );
    } on Object {
      await _stopQuietly();
      if (!isClosed) {
        emit(state.copyWith(loading: false, hasError: true, clearOffer: true));
      }
    }
  }

  Future<void> saveSettings({
    required List<SshReachabilityEndpoint> extraEndpoints,
    required String relayUrl,
  }) async {
    emit(state.copyWith(saving: true, hasError: false));
    try {
      await _settingsStore.save(
        extraEndpoints: extraEndpoints,
        relayUrl: relayUrl,
      );
      if (!isClosed) {
        emit(
          state.copyWith(
            extraEndpoints: List.unmodifiable(extraEndpoints),
            relayUrl: relayUrl.trim(),
            saving: false,
          ),
        );
      }
    } on Object {
      if (!isClosed) {
        emit(state.copyWith(saving: false, hasError: true));
      }
    }
  }

  Future<void> revokeDevice(String deviceId) async {
    try {
      await _authorizedKeys.revokeDevice(deviceId);
      if (!isClosed) {
        emit(state.copyWith(pairedDevices: await _loadPairedDevices()));
      }
    } on Object {
      if (!isClosed) emit(state.copyWith(hasError: true));
    }
  }

  Future<void> closeQrSession() async {
    if (!_qrSessionVisible) return;
    _qrSessionVisible = false;
    _operationId += 1;
    await _agent.stopQrSession();
    if (!isClosed) {
      emit(state.copyWith(loading: false, clearOffer: true));
    }
  }

  Future<void> _startFor(String address) => _agent.startQrSession(
    advertiseAddress: address,
    username: _username,
    displayName: _displayName,
    appDataRoot: _appDataRoot,
  );

  Future<List<ConnectPairedDevice>> _loadPairedDevices() async {
    final devices = await _authorizedKeys.listDevices();
    return devices
        .map(
          (device) =>
              ConnectPairedDevice(deviceId: device.deviceId, name: device.name),
        )
        .toList(growable: false);
  }

  Future<void> _stopQuietly() async {
    try {
      await _agent.stopQrSession();
    } on Object {
      // Preserve the originating operation failure for the UI state.
    }
  }

  bool _isCurrent(int operationId) =>
      !isClosed && _qrSessionVisible && operationId == _operationId;

  @override
  Future<void> close() async {
    await closeQrSession();
    return super.close();
  }
}
