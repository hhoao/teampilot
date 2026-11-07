import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/tcp_reachability_probe.dart';
import 'package:teampilot/services/storage/home_connect_attempt.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeProbe implements TcpReachabilityProbe {
  _FakeProbe(this.reachable);
  final bool reachable;
  int calls = 0;
  @override
  Future<bool> isReachable(
    String host,
    int port, {
    required Duration timeout,
  }) async {
    calls++;
    return reachable;
  }
}

SshProfile _profile() => SshProfile(
  id: 'p1',
  name: 'p1',
  host: '10.0.0.9',
  port: 22,
  username: 'u',
  authType: SshAuthType.privateKey,
  createdAt: 0,
  updatedAt: 0,
);

RuntimeContext _ctx({required bool fromCache}) => RuntimeContext(
  target: RuntimeTarget.local(),
  filesystem: InMemoryFilesystem(),
  home: '/h',
  cwd: '/h',
  appDataRoot: '/app',
  paths: const AppPaths('/app'),
  pathsFromCache: fromCache,
);

void main() {
  test('tcp unreachable short-circuits without resolving', () async {
    final probe = _FakeProbe(false);
    var resolved = 0;
    final attempt = HomeConnectAttempt(
      probe: probe,
      resolve: () async {
        resolved++;
        return _ctx(fromCache: false);
      },
      profileById: (_) => _profile(),
    );
    final result = await attempt.run('p1');
    expect(result.reachable, isFalse);
    expect(result.errorKind, HomeErrorKind.tcpUnreachable);
    expect(resolved, 0);
  });

  test('cache context is carried on tcp unreachable', () async {
    final cached = _ctx(fromCache: true);
    final attempt = HomeConnectAttempt(
      probe: _FakeProbe(false),
      resolve: () async => _ctx(fromCache: false),
      cacheContext: () async => cached,
      profileById: (_) => _profile(),
    );
    final result = await attempt.run('p1');
    expect(result.reachable, isFalse);
    expect(result.errorKind, HomeErrorKind.tcpUnreachable);
    expect(result.context, same(cached));
  });

  test('throwing cache context yields unreachable without context', () async {
    final attempt = HomeConnectAttempt(
      probe: _FakeProbe(false),
      resolve: () async => _ctx(fromCache: false),
      cacheContext: () async => throw StateError('no cached paths'),
      profileById: (_) => _profile(),
    );
    final result = await attempt.run('p1');
    expect(result.reachable, isFalse);
    expect(result.errorKind, HomeErrorKind.tcpUnreachable);
    expect(result.context, isNull);
  });

  test(
    'reachable + cached fallback reports unreachable transportError',
    () async {
      final attempt = HomeConnectAttempt(
        probe: _FakeProbe(true),
        resolve: () async => _ctx(fromCache: true),
        profileById: (_) => _profile(),
      );
      final result = await attempt.run('p1');
      expect(result.reachable, isFalse);
      expect(result.errorKind, HomeErrorKind.transportError);
    },
  );

  test('reachable + live resolve reports connected with context', () async {
    final attempt = HomeConnectAttempt(
      probe: _FakeProbe(true),
      resolve: () async => _ctx(fromCache: false),
      profileById: (_) => _profile(),
    );
    final result = await attempt.run('p1');
    expect(result.reachable, isTrue);
    expect(result.context, isNotNull);
  });

  test('resolve over budget reports sshTimeout', () async {
    final attempt = HomeConnectAttempt(
      probe: _FakeProbe(true),
      resolve: () => Completer<RuntimeContext>().future,
      profileById: (_) => _profile(),
      connectBudget: const Duration(milliseconds: 20),
    );
    final result = await attempt.run('p1');
    expect(result.reachable, isFalse);
    expect(result.errorKind, HomeErrorKind.sshTimeout);
  });

  test('SSH auth failures classify as authFailed', () async {
    final attempt = HomeConnectAttempt(
      probe: _FakeProbe(true),
      resolve: () async => throw SSHAuthFailError('permission denied'),
      profileById: (_) => _profile(),
    );
    final result = await attempt.run('p1');
    expect(result.reachable, isFalse);
    expect(result.errorKind, HomeErrorKind.authFailed);
  });

  test('non-auth resolve failures stay transportError', () async {
    final attempt = HomeConnectAttempt(
      probe: _FakeProbe(true),
      resolve: () async => throw StateError('connection reset'),
      profileById: (_) => _profile(),
    );
    final result = await attempt.run('p1');
    expect(result.reachable, isFalse);
    expect(result.errorKind, HomeErrorKind.transportError);
  });
}
