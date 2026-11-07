import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/home_connection_cubit.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_connect_attempt.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/in_memory_filesystem.dart';

RuntimeContext _ctx() => RuntimeContext(
  target: RuntimeTarget.local(),
  filesystem: InMemoryFilesystem(),
  home: '/h',
  cwd: '/h',
  appDataRoot: '/app',
  paths: const AppPaths('/app'),
);

void main() {
  test(
    'connectOnce success transitions to connected and fires onConnected',
    () async {
      var connected = 0;
      final cubit = HomeConnectionCubit(
        connect: () async => HomeConnectResult.connected(_ctx()),
        cancelRetry: () async {},
        resumeRetry: () async {},
        onConnected: () => connected++,
      );
      await cubit.connectOnce();
      expect(cubit.state.status, HomeConnectionStatus.connected);
      expect(connected, 1);
    },
  );

  test(
    'connectOnce failure transitions to unreachable and does not fire onConnected',
    () async {
      var connected = 0;
      final cubit = HomeConnectionCubit(
        connect: () async =>
            const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
        cancelRetry: () async {},
        resumeRetry: () async {},
        onConnected: () => connected++,
      );
      await cubit.connectOnce();
      expect(cubit.state.status, HomeConnectionStatus.unreachable);
      expect(cubit.state.lastErrorKind, HomeErrorKind.tcpUnreachable);
      expect(connected, 0);
    },
  );

  test(
    'cancelRetry stops retries and keeps unreachable; retryNow resets attempt',
    () async {
      var cancelled = 0;
      var resume = 0;
      final cubit = HomeConnectionCubit(
        connect: () async =>
            const HomeConnectResult.unreachable(HomeErrorKind.sshTimeout),
        cancelRetry: () async => cancelled++,
        resumeRetry: () async => resume++,
        onConnected: () {},
      );
      await cubit.connectOnce();
      await cubit.cancelRetry();
      expect(cancelled, 1);
      expect(cubit.state.status, HomeConnectionStatus.unreachable);
      await cubit.retryNow();
      expect(resume, 1);
      expect(cubit.state.attempt, 0);
    },
  );

  test(
    'markBackgroundAttempt sets reconnecting and attempt; markReconnected recovers',
    () async {
      var connected = 0;
      final cubit = HomeConnectionCubit(
        connect: () async =>
            const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
        cancelRetry: () async {},
        resumeRetry: () async {},
        onConnected: () => connected++,
      );
      await cubit.connectOnce();
      cubit.markBackgroundAttempt(3);
      expect(cubit.state.status, HomeConnectionStatus.reconnecting);
      expect(cubit.state.attempt, 3);
      expect(cubit.state.canCancelRetry, isTrue);
      expect(cubit.state.canRetryNow, isTrue);

      cubit.markReconnected();
      expect(cubit.state.status, HomeConnectionStatus.connected);
      expect(cubit.state.attempt, 0);
      expect(connected, 1);
    },
  );

  test('successful retry clears the last error kind', () async {
    var reachable = false;
    final cubit = HomeConnectionCubit(
      connect: () async => reachable
          ? HomeConnectResult.connected(_ctx())
          : const HomeConnectResult.unreachable(HomeErrorKind.sshTimeout),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
    );
    await cubit.connectOnce();
    expect(cubit.state.lastErrorKind, HomeErrorKind.sshTimeout);
    reachable = true;
    await cubit.retryNow();
    expect(cubit.state.status, HomeConnectionStatus.connected);
    expect(cubit.state.lastErrorKind, isNull);
  });

  test('carries home target identity through connectOnce', () async {
    final cubit = HomeConnectionCubit(
      profileId: 'p1',
      host: '10.0.0.9',
      port: 22,
      connect: () async =>
          const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
    );
    expect(cubit.state.profileId, 'p1');
    expect(cubit.state.host, '10.0.0.9');
    expect(cubit.state.port, 22);

    await cubit.connectOnce();
    expect(cubit.state.status, HomeConnectionStatus.unreachable);
    expect(cubit.state.profileId, 'p1');
    expect(cubit.state.host, '10.0.0.9');
    expect(cubit.state.port, 22);
  });

  test('markInitial seeds connected without network or onConnected', () async {
    var connected = 0;
    var connectCalls = 0;
    final cubit = HomeConnectionCubit(
      connect: () async {
        connectCalls++;
        return HomeConnectResult.connected(_ctx());
      },
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () => connected++,
    );
    cubit.markInitial(HomeConnectResult.connected(_ctx()));
    expect(cubit.state.status, HomeConnectionStatus.connected);
    expect(cubit.state.attempt, 0);
    expect(cubit.state.lastErrorKind, isNull);
    expect(connectCalls, 0);
    expect(connected, 0);
  });

  test('markInitial seeds unreachable with the error kind', () {
    final cubit = HomeConnectionCubit(
      connect: () async =>
          const HomeConnectResult.unreachable(HomeErrorKind.unknown),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
    );
    cubit.markInitial(
      const HomeConnectResult.unreachable(HomeErrorKind.authFailed),
    );
    expect(cubit.state.status, HomeConnectionStatus.unreachable);
    expect(cubit.state.attempt, 0);
    expect(cubit.state.lastErrorKind, HomeErrorKind.authFailed);
  });

  test('throwing connect callback lands unreachable, not connecting', () async {
    final cubit = HomeConnectionCubit(
      connect: () async => throw StateError('boom'),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
    );
    await cubit.connectOnce();
    expect(cubit.state.status, HomeConnectionStatus.unreachable);
    expect(cubit.state.lastErrorKind, HomeErrorKind.unknown);
  });

  test(
    'throwing resumeRetry lands unreachable instead of a permanent spinner',
    () async {
      var connectCalls = 0;
      final cubit = HomeConnectionCubit(
        connect: () async {
          connectCalls++;
          return HomeConnectResult.connected(_ctx());
        },
        cancelRetry: () async {},
        resumeRetry: () async => throw StateError('boom'),
        onConnected: () {},
      );
      await cubit.retryNow();
      expect(cubit.state.status, HomeConnectionStatus.unreachable);
      expect(cubit.state.lastErrorKind, HomeErrorKind.unknown);
      expect(connectCalls, 0);
    },
  );

  test(
    'a background retry while connected does not blank the surface',
    () async {
      final cubit = HomeConnectionCubit(
        connect: () async => HomeConnectResult.connected(_ctx()),
        cancelRetry: () async {},
        resumeRetry: () async {},
        onConnected: () {},
        profileId: 'p1',
      );
      await cubit.connectOnce();
      expect(cubit.state.status, HomeConnectionStatus.connected);

      cubit.markBackgroundAttempt(3);

      // A mid-session Wi-Fi → LTE blip must not swap the editor/terminal for the
      // connection page: the surface stays `connected` until recovery gives up.
      expect(cubit.state.status, HomeConnectionStatus.connected);
      expect(cubit.state.attempt, 0);
    },
  );

  test(
    'rebind moves the cubit onto a new home id and resets to connecting',
    () {
      final cubit = HomeConnectionCubit(
        connect: () async =>
            const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
        cancelRetry: () async {},
        resumeRetry: () async {},
        onConnected: () {},
        profileId: 'old',
        host: 'old.example.com',
        port: 22,
      );
      cubit.markInitial(
        const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
      );

      cubit.rebind(profileId: 'new', host: 'new.example.com', port: 2222);

      expect(cubit.state.status, HomeConnectionStatus.connecting);
      expect(cubit.state.profileId, 'new');
      expect(cubit.state.host, 'new.example.com');
      expect(cubit.state.port, 2222);
      expect(cubit.state.attempt, 0);
      expect(cubit.state.lastErrorKind, isNull);
    },
  );

  test('rebind for the same home id refreshes identity but keeps status', () {
    final cubit = HomeConnectionCubit(
      connect: () async =>
          const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
      profileId: 'p1',
      host: 'old.example.com',
      port: 22,
    );
    cubit.markInitial(
      const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
    );

    cubit.rebind(profileId: 'p1', host: 'fixed.example.com', port: 2200);

    expect(cubit.state.status, HomeConnectionStatus.unreachable);
    expect(cubit.state.host, 'fixed.example.com');
    expect(cubit.state.port, 2200);
    expect(cubit.state.lastErrorKind, HomeErrorKind.tcpUnreachable);
  });

  test('markRestartRequired closes the gate without a retry action', () {
    final cubit = HomeConnectionCubit(
      connect: () async => HomeConnectResult.connected(_ctx()),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
      profileId: 'p1',
    );
    cubit.markReconnected();

    cubit.markRestartRequired();

    expect(cubit.state.status, HomeConnectionStatus.restartRequired);
    expect(cubit.state.requiresRestart, isTrue);
    expect(cubit.state.canRetryNow, isFalse);
    expect(cubit.state.canCancelRetry, isFalse);
  });
}
