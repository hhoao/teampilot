import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/github/github_credentials_store.dart';
import '../services/github/github_device_flow_auth.dart';

enum GithubAccountStatus { unknown, disconnected, requesting, waiting, connected }

class GithubAccountState extends Equatable {
  const GithubAccountState({
    this.status = GithubAccountStatus.unknown,
    this.login,
    this.source,
    this.userCode,
    this.verificationUri,
    this.errorMessage,
    this.deviceFlowAvailable = false,
  });

  final GithubAccountStatus status;
  final String? login;
  final GithubCredentialSource? source;
  final String? userCode;
  final String? verificationUri;
  final String? errorMessage;
  final bool deviceFlowAvailable;

  GithubAccountState copyWith({
    GithubAccountStatus? status,
    String? login,
    GithubCredentialSource? source,
    String? userCode,
    String? verificationUri,
    String? errorMessage,
    bool? deviceFlowAvailable,
    bool clearLogin = false,
    bool clearSource = false,
    bool clearUserCode = false,
    bool clearVerificationUri = false,
    bool clearErrorMessage = false,
  }) {
    return GithubAccountState(
      status: status ?? this.status,
      login: clearLogin ? null : (login ?? this.login),
      source: clearSource ? null : (source ?? this.source),
      userCode: clearUserCode ? null : (userCode ?? this.userCode),
      verificationUri: clearVerificationUri
          ? null
          : (verificationUri ?? this.verificationUri),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      deviceFlowAvailable: deviceFlowAvailable ?? this.deviceFlowAvailable,
    );
  }

  @override
  List<Object?> get props => [
    status,
    login,
    source,
    userCode,
    verificationUri,
    errorMessage,
    deviceFlowAvailable,
  ];
}

class GithubAccountCubit extends Cubit<GithubAccountState> {
  GithubAccountCubit({
    required GithubCredentialsStore store,
    required GithubDeviceFlowAuth? deviceFlow,
    required Future<void> Function(Uri uri) openUrl,
    required Future<String> Function(String token) fetchLogin,
    Future<void> Function(Duration delay)? delay,
    bool? deviceFlowAvailable,
  }) : _store = store,
       _deviceFlow = deviceFlow,
       _openUrl = openUrl,
       _fetchLogin = fetchLogin,
       _delay = delay ?? Future<void>.delayed,
       super(
         GithubAccountState(
           deviceFlowAvailable: deviceFlowAvailable ?? deviceFlow != null,
         ),
       );

  static const _authDeniedMessage = 'GitHub authorization cancelled';
  static const _authExpiredMessage = 'Authorization expired. Try again.';
  static const _networkErrorMessage = 'Could not reach GitHub. Try again.';
  static const _deviceFlowUnavailableMessage =
      'GitHub sign-in is unavailable in this build. Use a personal access token.';

  final GithubCredentialsStore _store;
  final GithubDeviceFlowAuth? _deviceFlow;
  final Future<void> Function(Uri uri) _openUrl;
  final Future<String> Function(String token) _fetchLogin;
  final Future<void> Function(Duration delay) _delay;

  int _connectGeneration = 0;

  Future<void> hydrate() async {
    await _store.migrateLegacyHubPublishTokenIfNeeded();

    final stored = await _store.readStored();
    if (stored != null) {
      var login = stored.login;
      if (login == null || login.isEmpty) {
        login = await _tryFetchLogin(stored.token);
        if (login != null) {
          if (stored.source == GithubCredentialSource.oauth) {
            await _store.saveOAuth(token: stored.token, login: login);
          } else {
            await _store.savePat(stored.token, login: login);
          }
        }
      }
      emit(
        state.copyWith(
          status: GithubAccountStatus.connected,
          login: login,
          source: stored.source,
          clearUserCode: true,
          clearVerificationUri: true,
          clearErrorMessage: true,
        ),
      );
      return;
    }

    final token = await _store.resolveToken();
    if (token != null && token.isNotEmpty) {
      emit(
        state.copyWith(
          status: GithubAccountStatus.connected,
          clearLogin: true,
          clearSource: true,
          clearUserCode: true,
          clearVerificationUri: true,
          clearErrorMessage: true,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: GithubAccountStatus.disconnected,
        clearLogin: true,
        clearSource: true,
        clearUserCode: true,
        clearVerificationUri: true,
        clearErrorMessage: true,
      ),
    );
  }

  Future<void> connect() async {
    if (!state.deviceFlowAvailable || _deviceFlow == null) {
      emit(
        state.copyWith(
          status: GithubAccountStatus.disconnected,
          errorMessage: _deviceFlowUnavailableMessage,
          clearUserCode: true,
          clearVerificationUri: true,
        ),
      );
      return;
    }

    final generation = ++_connectGeneration;
    emit(
      state.copyWith(
        status: GithubAccountStatus.requesting,
        clearErrorMessage: true,
        clearUserCode: true,
        clearVerificationUri: true,
      ),
    );

    try {
      final start = await _deviceFlow.start();
      if (!_isActiveConnect(generation)) return;

      final browserUri = start.browserUri;
      try {
        await _openUrl(browserUri);
      } on Object {
        // Browser failure should not block waiting/polling.
      }

      if (!_isActiveConnect(generation)) return;
      emit(
        state.copyWith(
          status: GithubAccountStatus.waiting,
          userCode: start.userCode,
          verificationUri: browserUri.toString(),
        ),
      );

      await _pollUntilComplete(
        generation: generation,
        deviceCode: start.deviceCode,
        interval: start.interval,
      );
    } on Object {
      if (!_isActiveConnect(generation)) return;
      emit(
        state.copyWith(
          status: GithubAccountStatus.disconnected,
          errorMessage: _networkErrorMessage,
          clearUserCode: true,
          clearVerificationUri: true,
        ),
      );
    }
  }

  Future<void> cancelConnect() async {
    _connectGeneration++;
    emit(
      state.copyWith(
        status: GithubAccountStatus.disconnected,
        clearUserCode: true,
        clearVerificationUri: true,
      ),
    );
  }

  Future<void> reopenBrowser() async {
    final uriRaw = state.verificationUri;
    if (uriRaw == null || uriRaw.isEmpty) return;
    try {
      await _openUrl(Uri.parse(uriRaw));
    } on Object {
      // Reopen is best-effort; waiting UI still shows the URL.
    }
  }

  Future<void> disconnect() => _clearStoredAndDisconnect();

  Future<void> switchAccount() => _clearStoredAndDisconnect();

  Future<void> savePat(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;

    final login = await _tryFetchLogin(trimmed);
    await _store.savePat(trimmed, login: login);
    emit(
      state.copyWith(
        status: GithubAccountStatus.connected,
        login: login,
        source: GithubCredentialSource.pat,
        clearUserCode: true,
        clearVerificationUri: true,
        clearErrorMessage: true,
      ),
    );
  }

  Future<void> onUnauthorized() async {
    await _store.clearStored();
    emit(
      state.copyWith(
        status: GithubAccountStatus.disconnected,
        errorMessage: _authExpiredMessage,
        clearLogin: true,
        clearSource: true,
        clearUserCode: true,
        clearVerificationUri: true,
      ),
    );
  }

  Future<void> _clearStoredAndDisconnect() async {
    await _store.clearStored();
    emit(
      state.copyWith(
        status: GithubAccountStatus.disconnected,
        clearLogin: true,
        clearSource: true,
        clearUserCode: true,
        clearVerificationUri: true,
        clearErrorMessage: true,
      ),
    );
  }

  Future<void> _pollUntilComplete({
    required int generation,
    required String deviceCode,
    required int interval,
  }) async {
    var pollInterval = interval;
    while (_isActiveConnect(generation)) {
      await _delay(Duration(seconds: pollInterval));
      if (!_isActiveConnect(generation)) return;

      final result = await _deviceFlow!.pollOnce(
        deviceCode,
        interval: pollInterval,
      );

      switch (result) {
        case GithubDeviceFlowPollPending():
          continue;
        case GithubDeviceFlowPollSlowDown(:final newInterval):
          pollInterval = newInterval;
          continue;
        case GithubDeviceFlowPollDenied():
          if (!_isActiveConnect(generation)) return;
          emit(
            state.copyWith(
              status: GithubAccountStatus.disconnected,
              errorMessage: _authDeniedMessage,
              clearUserCode: true,
              clearVerificationUri: true,
            ),
          );
          return;
        case GithubDeviceFlowPollExpired():
          if (!_isActiveConnect(generation)) return;
          emit(
            state.copyWith(
              status: GithubAccountStatus.disconnected,
              errorMessage: _authExpiredMessage,
              clearUserCode: true,
              clearVerificationUri: true,
            ),
          );
          return;
        case GithubDeviceFlowPollSuccess(:final token):
          if (!_isActiveConnect(generation)) return;
          final login = await _fetchLogin(token);
          await _store.saveOAuth(token: token, login: login);
          emit(
            state.copyWith(
              status: GithubAccountStatus.connected,
              login: login,
              source: GithubCredentialSource.oauth,
              clearUserCode: true,
              clearVerificationUri: true,
              clearErrorMessage: true,
            ),
          );
          return;
      }
    }
  }

  bool _isActiveConnect(int generation) {
    return !isClosed && generation == _connectGeneration;
  }

  Future<String?> _tryFetchLogin(String token) async {
    try {
      final login = await _fetchLogin(token);
      return login.isEmpty ? null : login;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> close() {
    _connectGeneration++;
    return super.close();
  }
}
