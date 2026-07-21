import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:teampilot/cubits/github_account_cubit.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/github/github_credentials_store.dart';
import 'package:teampilot/services/github/github_device_flow_auth.dart';

class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

GithubDeviceFlowAuth controllableDeviceFlowAuth({
  required Future<GithubDeviceFlowPollResult> Function(
    int pollCount,
    String deviceCode,
    int interval,
  )
  onPoll,
}) {
  var pollCount = 0;
  return GithubDeviceFlowAuth(
    clientId: 'test-client-id',
    post: (url, {headers, body, encoding}) async {
      if (url.path.endsWith('/device/code')) {
        return http.Response(
          jsonEncode({
            'device_code': 'device-abc',
            'user_code': 'ABCD-1234',
            'verification_uri': 'https://github.com/login/device',
            'verification_uri_complete':
                'https://github.com/login/device?user_code=ABCD-1234',
            'expires_in': 900,
            'interval': 1,
          }),
          200,
        );
      }
      pollCount++;
      final interval = _parseInterval(body as String?);
      return http.Response(
        jsonEncode(
          _pollResultToJson(
            await onPoll(pollCount, 'device-abc', interval),
          ),
        ),
        200,
      );
    },
  );
}

int _parseInterval(String? body) {
  if (body == null) return 1;
  for (final part in body.split('&')) {
    if (part.startsWith('interval=')) {
      return int.parse(part.split('=').last);
    }
  }
  return 1;
}

Map<String, dynamic> _pollResultToJson(GithubDeviceFlowPollResult result) {
  return switch (result) {
    GithubDeviceFlowPollPending() => {'error': 'authorization_pending'},
    GithubDeviceFlowPollSlowDown(:final newInterval) => {
      'error': 'slow_down',
      'interval': newInterval,
    },
    GithubDeviceFlowPollDenied() => {'error': 'access_denied'},
    GithubDeviceFlowPollExpired() => {'error': 'expired_token'},
    GithubDeviceFlowPollSuccess(:final token) => {'access_token': token},
  };
}

Future<void> yieldToEventLoop(Duration duration) =>
    Future<void>.delayed(Duration.zero);

GithubAccountCubit createCubit({
  required GithubCredentialsStore store,
  GithubDeviceFlowAuth? deviceFlow,
  Future<void> Function(Uri uri)? openUrl,
  Future<String> Function(String token)? fetchLogin,
  Future<void> Function(Duration delay)? delay,
  bool deviceFlowAvailable = true,
}) {
  return GithubAccountCubit(
    store: store,
    deviceFlow: deviceFlow,
    openUrl: openUrl ?? (_) async {},
    fetchLogin: fetchLogin ?? (_) async => 'octocat',
    delay: delay ?? yieldToEventLoop,
    deviceFlowAvailable: deviceFlowAvailable,
  );
}

Future<void> pumpUntil(
  bool Function() predicate, {
  int maxAttempts = 50,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for predicate.');
}

void main() {
  group('GithubAccountCubit.hydrate', () {
    test('emits connected when stored oauth token exists', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      await store.saveOAuth(token: 'gho_test', login: 'alice');

      final cubit = createCubit(store: store);
      addTearDown(cubit.close);

      await cubit.hydrate();

      expect(cubit.state.status, GithubAccountStatus.connected);
      expect(cubit.state.login, 'alice');
      expect(cubit.state.source, GithubCredentialSource.oauth);
    });

    test('fetches login when stored token exists without login', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      await store.savePat('ghp_test');

      final cubit = createCubit(
        store: store,
        fetchLogin: (_) async => 'bob',
      );
      addTearDown(cubit.close);

      await cubit.hydrate();

      expect(cubit.state.status, GithubAccountStatus.connected);
      expect(cubit.state.login, 'bob');
      expect(cubit.state.source, GithubCredentialSource.pat);
      final snapshot = await store.readStored();
      expect(snapshot?.login, 'bob');
    });

    test('emits connected when only env token resolves', () async {
      final store = GithubCredentialsStore(
        kv: InMemorySecureKeyValueStore(),
        readEnvToken: () => 'ghp_env',
      );

      final cubit = createCubit(store: store);
      addTearDown(cubit.close);

      await cubit.hydrate();

      expect(cubit.state.status, GithubAccountStatus.connected);
      expect(cubit.state.login, isNull);
      expect(cubit.state.source, isNull);
    });

    test('emits disconnected when no token resolves', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());

      final cubit = createCubit(store: store);
      addTearDown(cubit.close);

      await cubit.hydrate();

      expect(cubit.state.status, GithubAccountStatus.disconnected);
    });
  });

  group('GithubAccountCubit.connect', () {
    test('enters waiting with user code then connects on poll success', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      final openedUrls = <Uri>[];
      final statuses = <GithubAccountStatus>[];
      final auth = controllableDeviceFlowAuth(
        onPoll: (count, deviceCode, interval) async {
          if (count == 1) return const GithubDeviceFlowPollPending();
          return const GithubDeviceFlowPollSuccess('gho_new');
        },
      );

      final cubit = createCubit(
        store: store,
        deviceFlow: auth,
        openUrl: (uri) async => openedUrls.add(uri),
        fetchLogin: (_) async => 'carol',
      );
      addTearDown(cubit.close);
      final subscription = cubit.stream.listen(
        (state) => statuses.add(state.status),
      );
      addTearDown(subscription.cancel);
      await cubit.hydrate();

      await cubit.connect();

      expect(statuses, contains(GithubAccountStatus.waiting));
      expect(cubit.state.userCode, isNull);
      expect(cubit.state.status, GithubAccountStatus.connected);
      expect(cubit.state.login, 'carol');
      expect(cubit.state.source, GithubCredentialSource.oauth);
      expect(openedUrls.single.toString(),
          'https://github.com/login/device?user_code=ABCD-1234');
      final snapshot = await store.readStored();
      expect(snapshot?.token, 'gho_new');
      expect(snapshot?.login, 'carol');
    });

    test('enters waiting when openUrl throws', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      final auth = controllableDeviceFlowAuth(
        onPoll: (_, __, ___) async => const GithubDeviceFlowPollPending(),
      );

      final cubit = createCubit(
        store: store,
        deviceFlow: auth,
        openUrl: (_) async => throw Exception('browser failed'),
      );
      addTearDown(cubit.close);
      await cubit.hydrate();

      unawaited(cubit.connect());
      await pumpUntil(
        () => cubit.state.status == GithubAccountStatus.waiting,
      );

      expect(cubit.state.userCode, 'ABCD-1234');

      await cubit.cancelConnect();
      expect(cubit.state.status, GithubAccountStatus.disconnected);
    });

    test('emits disconnected with message on access_denied', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      final auth = controllableDeviceFlowAuth(
        onPoll: (_, __, ___) async => const GithubDeviceFlowPollDenied(),
      );

      final cubit = createCubit(store: store, deviceFlow: auth);
      addTearDown(cubit.close);
      await cubit.hydrate();

      await cubit.connect();

      expect(cubit.state.status, GithubAccountStatus.disconnected);
      expect(cubit.state.errorMessage, 'GitHub authorization cancelled');
    });

    test('emits disconnected with message on expired_token', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      final auth = controllableDeviceFlowAuth(
        onPoll: (_, __, ___) async => const GithubDeviceFlowPollExpired(),
      );

      final cubit = createCubit(store: store, deviceFlow: auth);
      addTearDown(cubit.close);
      await cubit.hydrate();

      await cubit.connect();

      expect(cubit.state.status, GithubAccountStatus.disconnected);
      expect(cubit.state.errorMessage, 'Authorization expired. Try again.');
    });

    test('cancelConnect stops polling before success', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      final pollCompleter = Completer<void>();
      var pollCount = 0;
      final auth = controllableDeviceFlowAuth(
        onPoll: (_, __, ___) async {
          pollCount++;
          if (pollCount == 1) {
            await pollCompleter.future;
          }
          return const GithubDeviceFlowPollSuccess('gho_should_not_save');
        },
      );

      final cubit = createCubit(store: store, deviceFlow: auth);
      addTearDown(cubit.close);
      await cubit.hydrate();

      unawaited(cubit.connect());
      await pumpUntil(
        () => cubit.state.status == GithubAccountStatus.waiting,
      );

      await cubit.cancelConnect();
      pollCompleter.complete();
      await pumpUntil(
        () => cubit.state.status == GithubAccountStatus.disconnected,
      );

      expect(cubit.state.status, GithubAccountStatus.disconnected);
      expect(await store.readStored(), isNull);
    });

    test('emits disconnected with message when start throws', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      final auth = GithubDeviceFlowAuth(
        clientId: 'test-client-id',
        post: (_, {headers, body, encoding}) async {
          throw Exception('network down');
        },
      );

      final cubit = createCubit(store: store, deviceFlow: auth);
      addTearDown(cubit.close);
      await cubit.hydrate();

      await cubit.connect();

      expect(cubit.state.status, GithubAccountStatus.disconnected);
      expect(cubit.state.errorMessage, 'Could not reach GitHub. Try again.');
      expect(await store.readStored(), isNull);
    });

    test('sets unavailable error when device flow is disabled', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      final auth = controllableDeviceFlowAuth(
        onPoll: (_, __, ___) async => const GithubDeviceFlowPollPending(),
      );

      final cubit = createCubit(
        store: store,
        deviceFlow: auth,
        deviceFlowAvailable: false,
      );
      addTearDown(cubit.close);
      await cubit.hydrate();

      await cubit.connect();

      expect(cubit.state.status, GithubAccountStatus.disconnected);
      expect(
        cubit.state.errorMessage,
        'GitHub sign-in is unavailable in this build. Use a personal access token.',
      );
      expect(await store.readStored(), isNull);
    });
  });

  group('GithubAccountCubit credentials actions', () {
    test('savePat stores token and emits connected with pat source', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());

      final cubit = createCubit(
        store: store,
        fetchLogin: (_) async => 'dana',
      );
      addTearDown(cubit.close);
      await cubit.hydrate();

      await cubit.savePat('ghp_saved');

      expect(cubit.state.status, GithubAccountStatus.connected);
      expect(cubit.state.login, 'dana');
      expect(cubit.state.source, GithubCredentialSource.pat);
      final snapshot = await store.readStored();
      expect(snapshot?.token, 'ghp_saved');
    });

    test('disconnect clears stored credentials only', () async {
      final store = GithubCredentialsStore(
        kv: InMemorySecureKeyValueStore(),
        readEnvToken: () => 'ghp_env',
      );
      await store.saveOAuth(token: 'gho_test', login: 'alice');

      final cubit = createCubit(store: store);
      addTearDown(cubit.close);
      await cubit.hydrate();

      await cubit.disconnect();

      expect(cubit.state.status, GithubAccountStatus.disconnected);
      expect(await store.readStored(), isNull);
      expect(await store.resolveToken(), 'ghp_env');
    });

    test('switchAccount clears stored credentials only', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      await store.saveOAuth(token: 'gho_test', login: 'alice');

      final cubit = createCubit(store: store);
      addTearDown(cubit.close);
      await cubit.hydrate();

      await cubit.switchAccount();

      expect(cubit.state.status, GithubAccountStatus.disconnected);
      expect(await store.readStored(), isNull);
    });

    test('onUnauthorized clears stored and shows expired message', () async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      await store.saveOAuth(token: 'gho_test', login: 'alice');

      final cubit = createCubit(store: store);
      addTearDown(cubit.close);
      await cubit.hydrate();

      await cubit.onUnauthorized();

      expect(cubit.state.status, GithubAccountStatus.disconnected);
      expect(cubit.state.errorMessage, 'Authorization expired. Try again.');
      expect(await store.readStored(), isNull);
    });
  });
}
