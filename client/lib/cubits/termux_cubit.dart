import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ssh_profile.dart';
import '../repositories/ssh_credential_store.dart';
import '../services/termux/apply_termux_connect_home.dart';
import '../services/termux/termux_config.dart';
import '../services/termux/termux_config_store.dart';
import '../services/termux/termux_key_material.dart';
import '../services/termux/termux_transport_profile.dart';

typedef TermuxConnectTestResult = ({bool ok, String message});

typedef TermuxConnectTester =
    Future<TermuxConnectTestResult> Function(SshProfile profile);

typedef TermuxPathsResolver =
    Future<({String? home, String? appDataRoot})> Function();

@immutable
class TermuxState extends Equatable {
  const TermuxState({
    this.config,
    this.connected = false,
    this.connecting = false,
    this.lastError,
  });

  final TermuxConfig? config;
  final bool connected;
  final bool connecting;
  final String? lastError;

  bool get isConfigured =>
      config != null && config!.username.trim().isNotEmpty;

  TermuxState copyWith({
    TermuxConfig? config,
    bool? connected,
    bool? connecting,
    String? lastError,
    bool clearLastError = false,
    bool clearConfig = false,
  }) {
    return TermuxState(
      config: clearConfig ? null : (config ?? this.config),
      connected: connected ?? this.connected,
      connecting: connecting ?? this.connecting,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [config, connected, connecting, lastError];
}

class TermuxCubit extends Cubit<TermuxState> {
  TermuxCubit({
    required TermuxConfigStore store,
    required SshCredentialStore credentials,
    required String nativeAppDataPath,
    required Future<void> Function(String homeId) selectHome,
    required TermuxConnectTester testConnect,
    void Function(TermuxConfig? config)? onConfigChanged,
    TermuxPathsResolver? resolvePathsAfterHomeSelect,
    Future<void> Function()? disconnectTransport,
    TermuxConfig? initialConfig,
  }) : _store = store,
       _credentials = credentials,
       _nativeAppDataPath = nativeAppDataPath,
       _selectHome = selectHome,
       _testConnect = testConnect,
       _onConfigChanged = onConfigChanged,
       _resolvePathsAfterHomeSelect = resolvePathsAfterHomeSelect,
       _disconnectTransport = disconnectTransport,
       super(TermuxState(config: initialConfig));

  final TermuxConfigStore _store;
  final SshCredentialStore _credentials;
  final String _nativeAppDataPath;
  final Future<void> Function(String homeId) _selectHome;
  final TermuxConnectTester _testConnect;
  final void Function(TermuxConfig? config)? _onConfigChanged;
  final TermuxPathsResolver? _resolvePathsAfterHomeSelect;
  final Future<void> Function()? _disconnectTransport;

  Future<void> hydrate() async {
    final config = await _store.load();
    emit(
      state.copyWith(
        config: config,
        connected: false,
        connecting: false,
        clearLastError: true,
        clearConfig: config == null,
      ),
    );
    _notifyConfigChanged(config);
  }

  Future<void> saveConfig(TermuxConfig config) async {
    await _store.save(config);
    await TermuxKeyMaterial.ensureKeyPair(
      nativeAppDataPath: _nativeAppDataPath,
      credentials: _credentials,
    );
    emit(state.copyWith(config: config, clearLastError: true));
    _notifyConfigChanged(config);
  }

  Future<void> connect() async {
    final config = state.config;
    if (config == null || config.username.trim().isEmpty) {
      emit(
        state.copyWith(
          connected: false,
          connecting: false,
          lastError: 'Termux is not configured',
        ),
      );
      return;
    }

    emit(state.copyWith(connecting: true, connected: false, clearLastError: true));

    try {
      await TermuxKeyMaterial.ensureKeyPair(
        nativeAppDataPath: _nativeAppDataPath,
        credentials: _credentials,
      );

      final profile = termuxTransportProfile(config);
      final result = await _testConnect(profile);
      if (!result.ok) {
        emit(
          state.copyWith(
            connected: false,
            connecting: false,
            lastError: result.message.isEmpty
                ? 'Termux connection failed'
                : result.message,
          ),
        );
        return;
      }

      await applyTermuxConnectHome(selectHome: _selectHome);

      var nextConfig = config;
      final resolvePaths = _resolvePathsAfterHomeSelect;
      if (resolvePaths != null) {
        final paths = await resolvePaths();
        nextConfig = config.copyWith(
          lastHome: paths.home ?? config.lastHome,
          lastAppDataRoot: paths.appDataRoot ?? config.lastAppDataRoot,
        );
        if (nextConfig != config) {
          await _store.save(nextConfig);
          _notifyConfigChanged(nextConfig);
        }
      }

      emit(
        state.copyWith(
          config: nextConfig,
          connected: true,
          connecting: false,
          clearLastError: true,
        ),
      );
    } on Object catch (error) {
      emit(
        state.copyWith(
          connected: false,
          connecting: false,
          lastError: error.toString(),
        ),
      );
    }
  }

  Future<void> reconnect() => connect();

  Future<void> disconnect() async {
    final disconnectTransport = _disconnectTransport;
    if (disconnectTransport != null) {
      await disconnectTransport();
    }
    emit(
      state.copyWith(
        connected: false,
        connecting: false,
        clearLastError: true,
      ),
    );
  }

  Future<void> clearSetup() async {
    await _store.clear();
    try {
      await _credentials.deleteAll(TermuxKeyMaterial.credentialProfileId);
    } on Object {
      // Config/keys on disk are the source of truth for setup state.
    }
    await _deleteKeyFiles();
    await applyTermuxClearSetupHome(selectHome: _selectHome);
    emit(
      const TermuxState(
        connected: false,
        connecting: false,
      ),
    );
    _notifyConfigChanged(null);
  }

  Future<void> _deleteKeyFiles() async {
    for (final path in [
      TermuxKeyMaterial.privateKeyPath(_nativeAppDataPath),
      TermuxKeyMaterial.publicKeyPath(_nativeAppDataPath),
    ]) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  void _notifyConfigChanged(TermuxConfig? config) {
    _onConfigChanged?.call(config);
  }
}
