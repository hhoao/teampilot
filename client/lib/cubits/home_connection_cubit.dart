import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/storage/home_connect_attempt.dart';

enum HomeConnectionStatus { connecting, connected, unreachable, reconnecting }

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
  }) : _connect = connect,
       _cancelRetry = cancelRetry,
       _resumeRetry = resumeRetry,
       _onConnected = onConnected,
       super(const HomeConnectionState());

  final Future<HomeConnectResult> Function() _connect;
  final Future<void> Function() _cancelRetry;
  final Future<void> Function() _resumeRetry;
  final void Function() _onConnected;

  Future<void> connectOnce() async {
    emit(state.copyWith(status: HomeConnectionStatus.connecting));
    final result = await _connect();
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
    emit(state.copyWith(attempt: 0, status: HomeConnectionStatus.connecting));
    await _resumeRetry();
    await connectOnce();
  }

  Future<void> cancelRetry() async {
    await _cancelRetry();
    if (isClosed) return;
    emit(state.copyWith(status: HomeConnectionStatus.unreachable));
  }

  void markBackgroundAttempt(int attempt) {
    if (isClosed) return;
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
