import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/storage/home_connect_attempt.dart';
import '../utils/logging/logger.dart';

enum HomeConnectionStatus {
  connecting,
  connected,
  unreachable,
  reconnecting,

  /// The home transport is back but the published storage plane could not be
  /// moved onto it (first-ever-unreachable fallback). Unlike [unreachable]
  /// this is not retryable from the page: the user must restart the app so the
  /// SSH home resolves live before boot.
  restartRequired,
}

class HomeConnectionState extends Equatable {
  const HomeConnectionState({
    this.status = HomeConnectionStatus.connecting,
    this.profileId,
    this.host,
    this.port,
    this.attempt = 0,
    this.lastErrorKind,
  });

  final HomeConnectionStatus status;
  final String? profileId;
  final String? host;
  final int? port;
  final int attempt;
  final HomeErrorKind? lastErrorKind;

  bool get canCancelRetry => status == HomeConnectionStatus.reconnecting;
  bool get canRetryNow =>
      status == HomeConnectionStatus.unreachable ||
      status == HomeConnectionStatus.reconnecting;
  bool get requiresRestart => status == HomeConnectionStatus.restartRequired;

  static const Object _unset = Object();

  HomeConnectionState copyWith({
    HomeConnectionStatus? status,
    String? profileId,
    String? host,
    int? port,
    int? attempt,
    Object? lastErrorKind = _unset,
  }) => HomeConnectionState(
    status: status ?? this.status,
    profileId: profileId ?? this.profileId,
    host: host ?? this.host,
    port: port ?? this.port,
    attempt: attempt ?? this.attempt,
    lastErrorKind: identical(lastErrorKind, _unset)
        ? this.lastErrorKind
        : lastErrorKind as HomeErrorKind?,
  );

  @override
  List<Object?> get props => [
    status,
    profileId,
    host,
    port,
    attempt,
    lastErrorKind,
  ];
}

class HomeConnectionCubit extends Cubit<HomeConnectionState> {
  HomeConnectionCubit({
    required Future<HomeConnectResult> Function() connect,
    required Future<void> Function() cancelRetry,
    required Future<void> Function() resumeRetry,
    required void Function() onConnected,
    String? profileId,
    String? host,
    int? port,
  }) : _connect = connect,
       _cancelRetry = cancelRetry,
       _resumeRetry = resumeRetry,
       _onConnected = onConnected,
       super(HomeConnectionState(profileId: profileId, host: host, port: port));

  final Future<HomeConnectResult> Function() _connect;
  final Future<void> Function() _cancelRetry;
  final Future<void> Function() _resumeRetry;
  final void Function() _onConnected;

  Future<void> connectOnce() async {
    if (isClosed) return;
    emit(state.copyWith(status: HomeConnectionStatus.connecting));
    final HomeConnectResult result;
    try {
      result = await _connect();
    } on Object catch (error) {
      // A throwing callback must never wedge the shell in `connecting`
      // (permanent spinner). Content-free fallback: no error text is kept.
      appLogger.w('[home] connect attempt failed: ${error.runtimeType}');
      if (isClosed) return;
      emit(
        state.copyWith(
          status: HomeConnectionStatus.unreachable,
          lastErrorKind: HomeErrorKind.unknown,
        ),
      );
      return;
    }
    if (isClosed) return;
    if (result.reachable) {
      emit(
        state.copyWith(
          status: HomeConnectionStatus.connected,
          attempt: 0,
          lastErrorKind: null,
        ),
      );
      _onConnected();
    } else {
      emit(
        state.copyWith(
          status: HomeConnectionStatus.unreachable,
          lastErrorKind: result.errorKind,
        ),
      );
    }
  }

  Future<void> retryNow() async {
    if (isClosed) return;
    emit(state.copyWith(attempt: 0, status: HomeConnectionStatus.connecting));
    try {
      await _resumeRetry();
    } on Object catch (error) {
      appLogger.w('[home] resume retry failed: ${error.runtimeType}');
      if (isClosed) return;
      emit(
        state.copyWith(
          status: HomeConnectionStatus.unreachable,
          lastErrorKind: HomeErrorKind.unknown,
        ),
      );
      return;
    }
    if (isClosed) return;
    await connectOnce();
  }

  Future<void> cancelRetry() async {
    await _cancelRetry();
    if (isClosed) return;
    emit(state.copyWith(status: HomeConnectionStatus.unreachable));
  }

  /// Surfaces background retry progress on the connection page.
  ///
  /// A healthy home can drop mid-session (Wi-Fi → LTE blip) and the
  /// coordinator starts retrying immediately. That must not blank the editor
  /// or terminal: only an already-down surface transitions to
  /// [HomeConnectionStatus.reconnecting].
  void markBackgroundAttempt(int attempt) {
    if (isClosed) return;
    if (state.status == HomeConnectionStatus.connected) return;
    emit(
      state.copyWith(
        status: HomeConnectionStatus.reconnecting,
        attempt: attempt,
      ),
    );
  }

  void markReconnected() {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: HomeConnectionStatus.connected,
        attempt: 0,
        lastErrorKind: null,
      ),
    );
    _onConnected();
  }

  /// Holds the startup gate on the connection page while a recovered SSH home
  /// has its storage plane rebound (the boot-time fallback was a native plane).
  void markPlaneRebinding() {
    if (isClosed) return;
    emit(state.copyWith(status: HomeConnectionStatus.connecting, attempt: 0));
  }

  /// Publishes the plane rebind as connected without replaying [onConnected]
  /// (the recovery callback that requested the rebind is already running).
  void markPlaneReady() {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: HomeConnectionStatus.connected,
        attempt: 0,
        lastErrorKind: null,
      ),
    );
  }

  /// The home transport recovered but the published storage plane could not be
  /// moved onto it; keep the gate closed until a restart resolves the SSH home
  /// before boot.
  void markRestartRequired() {
    if (isClosed) return;
    emit(
      state.copyWith(status: HomeConnectionStatus.restartRequired, attempt: 0),
    );
  }

  /// Re-points the cubit at the currently selected home target.
  ///
  /// [profileId], [host] and [port] describe the new target. The status only
  /// resets when the identity changed: a same-target identity refresh (e.g. an
  /// edited host that is retried right after) keeps the current surface.
  void rebind({String? profileId, String? host, int? port}) {
    if (isClosed) return;
    final identityChanged = state.profileId != profileId;
    emit(
      HomeConnectionState(
        status: identityChanged
            ? HomeConnectionStatus.connecting
            : state.status,
        profileId: profileId,
        host: host,
        port: port,
        attempt: identityChanged ? 0 : state.attempt,
        lastErrorKind: identityChanged ? null : state.lastErrorKind,
      ),
    );
  }

  /// Seeds the state from an already-computed result without any network I/O
  /// and without firing [onConnected].
  void markInitial(HomeConnectResult result) {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: result.reachable
            ? HomeConnectionStatus.connected
            : HomeConnectionStatus.unreachable,
        attempt: 0,
        lastErrorKind: result.errorKind,
      ),
    );
  }
}
