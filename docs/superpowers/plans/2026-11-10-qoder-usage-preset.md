# Qoder 余额与用量查询预设 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two built-in Qoder usage presets (Global and CN) backed by a `qoder-usage` adapter that exchanges a Personal Access Token for a job token and displays plan, add-on, and organization credits.

**Architecture:** The preset supplies the region-specific usage URL and stores the PAT in the existing secret store as `apiKey`. A new adapter validates the URL against a fixed `openapi.qoder.*` allowlist, exchanges the PAT at `/api/v1/jobToken/exchange`, then queries `/api/v2/quota/usage` with the short-lived job token. It maps three quota buckets into existing `ProviderUsageMeasure`s and falls back to `totalUsagePercentage` when no bucket is present.

**Tech Stack:** Dart, Flutter, `ManagedProviderUsageAdapter`, `ProviderUsageHttpClient`, slang l10n, `dart run tool/run_tests.dart`.

## Global Constraints

- Never invoke `flutter test` directly. Always run `cd client && dart run tool/run_tests.dart <paths/options>`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Fast inner loop: `flutter analyze`; verify each task with its targeted test file; run the full suite once at the end.
- l10n: edit `client/lib/i18n/managedProviders_en.i18n.json` / `_zh.i18n.json`, then `cd client && dart run slang`. Never hand-edit generated `translations_*.g.dart`.
- Never include a PAT, job token, or response body in logs, URLs, snapshots, or error messages. No `print`.
- The adapter may only contact `openapi.qoder.sh` or `openapi.qoder.com.cn` over HTTPS at the two fixed paths.
- Do not modify unrelated working-tree files. Stage explicit paths in every commit; never `git add -A`.
- No new dependencies.

## File Structure

- `client/lib/services/provider_usage/adapters/qoder_usage_adapter.dart` (new): PAT exchange, usage fetch, bucket normalization, error mapping.
- `client/lib/services/provider_usage/managed_provider_presets.dart` (modify): two presets and their editor schema.
- `client/lib/app/app_shell.dart` (modify): import and register `QoderUsageAdapter`.
- `client/lib/l10n/l10n_extensions.dart` (modify): preset id → label/hint mapping.
- `client/lib/i18n/managedProviders_{en,zh}.i18n.json` (modify): four new strings.
- `client/lib/l10n/translations_{en,zh}.g.dart` (generated): run `dart run slang`.
- `client/test/services/provider_usage/qoder_usage_adapter_test.dart` (new): adapter request/response tests.
- `client/test/services/provider_usage/managed_provider_presets_test.dart` (modify): preset metadata and l10n coverage.
- `client/test/app/app_shell_provider_usage_bootstrap_test.dart` (modify): registry contains the new adapter.

---

### Task 1: Qoder adapter and default registration

**Files:**
- Create: `client/lib/services/provider_usage/adapters/qoder_usage_adapter.dart`
- Create: `client/test/services/provider_usage/qoder_usage_adapter_test.dart`
- Modify: `client/lib/app/app_shell.dart:317-321` (imports), `client/lib/app/app_shell.dart:487-497` (registry)
- Modify: `client/test/app/app_shell_provider_usage_bootstrap_test.dart:31-38` (registry assertion)

**Interfaces:**
- Consumes: `ManagedProvider`, `ProviderUsageSnapshot`, `ManagedProviderUsageAdapter`, `ProviderUsageHttpClient`, `ProviderCredentialResolver`, `ProviderCredentialScope`, `parseOfficialResetAt`, `decodeOfficialJsonObject`, `throwOfficialHttpStatus`.
- Produces: `class QoderUsageAdapter implements ManagedProviderUsageAdapter` with `static const String adapterId = 'qoder-usage'`; registered under that id in `buildDefaultManagedProviderUsageRegistry()`.

- [ ] **Step 1: Write the failing adapter test**

Create `client/test/services/provider_usage/qoder_usage_adapter_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/services/provider_usage/adapters/qoder_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);

  ManagedProvider provider({
    String url = 'https://openapi.qoder.sh/api/v2/quota/usage',
  }) => ManagedProvider(
    id: 'qoder-1',
    name: 'Qoder',
    kind: ManagedProviderKind.subscriptionQuota,
    adapterId: 'qoder-usage',
    endpointConfig: ManagedProviderEndpointConfig(
      url: url,
      method: 'GET',
      credentialField: 'apiKey',
    ),
    displayConfig: ManagedProviderDisplayConfig(
      unit: 'credits',
      decimalPlaces: 2,
    ),
  );

  Future<ProviderUsageSnapshot> fetch(
    _QueueHttp http, {
    Map<String, String> credentials = const {'apiKey': 'pt-test'},
    String url = 'https://openapi.qoder.sh/api/v2/quota/usage',
  }) => QoderUsageAdapter().fetch(
    provider(url: url),
    credentials: _Credentials(credentials),
    http: http,
    now: now,
  );

  Matcher queryError(ManagedProviderUsageQueryErrorCode code) =>
      isA<ManagedProviderUsageQueryError>().having(
        (error) => error.code,
        'code',
        code,
      );

  test('exchanges a PAT and maps plan, add-on, and org credits', () async {
    final http = _QueueHttp([_exchangeOk, _usageOk]);

    final snapshot = await fetch(http);

    expect(http.requests, hasLength(2));
    final exchange = http.requests.first;
    expect(exchange.method, 'POST');
    expect(
      exchange.uri.toString(),
      'https://openapi.qoder.sh/api/v1/jobToken/exchange',
    );
    expect(exchange.headers['content-type'], 'application/json');
    expect(exchange.headers['accept'], 'application/json');
    expect(exchange.headers['user-agent'], 'teampilot-qoder-usage/1.0');
    expect(exchange.headers['cosy-version'], '1.0.1');
    expect(exchange.headers['cosy-clienttype'], '5');
    expect(jsonDecode(exchange.body!), {'personal_token': 'pt-test'});

    final usage = http.requests.last;
    expect(usage.method, 'GET');
    expect(
      usage.uri.toString(),
      'https://openapi.qoder.sh/api/v2/quota/usage',
    );
    expect(usage.headers['authorization'], 'Bearer jt-test');
    expect(usage.headers['accept'], 'application/json');
    expect(usage.headers['user-agent'], 'teampilot-qoder-usage/1.0');
    expect(usage.headers.containsKey('cosy-version'), isFalse);

    expect(snapshot.providerId, 'qoder-1');
    expect(snapshot.status, ProviderUsageStatus.ready);
    expect(snapshot.fetchedAt, now.millisecondsSinceEpoch);
    expect(snapshot.measures.map((measure) => measure.label), [
      'Plan',
      'Add-on',
      'Org',
    ]);

    final plan = snapshot.measures[0];
    expect(plan.used, '1200');
    expect(plan.total, '3000');
    expect(plan.remaining, '1800');
    expect(plan.unit, 'credits');
    expect(plan.kind, ProviderUsageMeasureKind.quota);
    expect(plan.resetsAt, 1790000000000);

    final addOn = snapshot.measures[1];
    expect(addOn.used, '50');
    expect(addOn.total, '50');
    expect(addOn.remaining, '0');

    final org = snapshot.measures[2];
    expect(org.used, '10');
    expect(org.total, '100');
    expect(org.remaining, '90');
    expect(org.resetsAt, 1790000000000);
  });

  test('uses the CN openapi host when the preset URL is CN', () async {
    final http = _QueueHttp([_exchangeOk, _usageOk]);

    await fetch(
      http,
      url: 'https://openapi.qoder.com.cn/api/v2/quota/usage',
    );

    expect(http.requests.map((request) => request.uri.host), [
      'openapi.qoder.com.cn',
      'openapi.qoder.com.cn',
    ]);
    expect(http.requests.first.uri.path, '/api/v1/jobToken/exchange');
    expect(http.requests.last.uri.path, '/api/v2/quota/usage');
  });

  test('rejects non-allowlisted or malformed URLs without sending', () async {
    const urls = [
      'https://evil.example/api/v2/quota/usage',
      'http://openapi.qoder.sh/api/v2/quota/usage',
      'https://openapi.qoder.sh/api/v2/quota/other',
      'https://openapi.qoder.sh/api/v2/quota/usage?x=1',
      'https://openapi.qoder.sh:8443/api/v2/quota/usage',
      'https://openapi.qoder.sh/api/v2/quota/usage#frag',
    ];
    for (final url in urls) {
      final http = _QueueHttp([_exchangeOk, _usageOk]);
      await expectLater(
        fetch(http, url: url),
        throwsA(queryError(ManagedProviderUsageQueryErrorCode.unsupported)),
        reason: url,
      );
      expect(http.requests, isEmpty, reason: url);
    }
  });

  test('missing PAT fails with missingCredential', () async {
    final http = _QueueHttp([_exchangeOk, _usageOk]);

    await expectLater(
      fetch(http, credentials: const {}),
      throwsA(
        queryError(ManagedProviderUsageQueryErrorCode.missingCredential),
      ),
    );
    expect(http.requests, isEmpty);
  });

  for (final status in [400, 401, 403]) {
    test('exchange status $status maps to authenticationFailed', () async {
      final http = _QueueHttp([
        ProviderUsageHttpResponse(statusCode: status, body: '{}'),
      ]);

      await expectLater(
        fetch(http),
        throwsA(
          queryError(
            ManagedProviderUsageQueryErrorCode.authenticationFailed,
          ),
        ),
      );
      expect(http.requests, hasLength(1));
    });
  }

  test('exchange 500 maps to httpFailed', () async {
    final http = _QueueHttp([
      const ProviderUsageHttpResponse(statusCode: 500, body: '{}'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(queryError(ManagedProviderUsageQueryErrorCode.httpFailed)),
    );
  });

  test('usage 401 maps to authenticationFailed', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(statusCode: 401, body: '{}'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(
        queryError(ManagedProviderUsageQueryErrorCode.authenticationFailed),
      ),
    );
  });

  test('usage 500 maps to httpFailed', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(statusCode: 500, body: '{}'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(queryError(ManagedProviderUsageQueryErrorCode.httpFailed)),
    );
  });

  test('exchange response without a token fails with responseParseFailed', () async {
    final http = _QueueHttp([
      const ProviderUsageHttpResponse(statusCode: 200, body: '{}'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(
        queryError(ManagedProviderUsageQueryErrorCode.responseParseFailed),
      ),
    );
  });

  test('usage response that is not JSON fails with responseParseFailed', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(statusCode: 200, body: 'not-json'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(
        queryError(ManagedProviderUsageQueryErrorCode.responseParseFailed),
      ),
    );
  });

  test('usage response without buckets or percentage fails with responseParseFailed', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"expiresAt":1790000000000}',
      ),
    ]);

    await expectLater(
      fetch(http),
      throwsA(
        queryError(ManagedProviderUsageQueryErrorCode.responseParseFailed),
      ),
    );
  });

  test('renders only buckets present in the response', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body:
            '{"userQuota":{"total":10,"used":5,"remaining":5,"unit":"credits"}}',
      ),
    ]);

    final snapshot = await fetch(http);

    expect(snapshot.measures.map((measure) => measure.label), ['Plan']);
    expect(snapshot.measures.single.resetsAt, isNull);
  });

  test('org package falls back to total when cap is absent', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body:
            '{"orgResourcePackage":{"total":100,"used":10,"remaining":90}}',
      ),
    ]);

    final snapshot = await fetch(http);

    expect(snapshot.measures.single.label, 'Org');
    expect(snapshot.measures.single.total, '100');
    expect(snapshot.measures.single.unit, 'credits');
  });

  test('falls back to totalUsagePercentage when no buckets exist', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"totalUsagePercentage":40,"expiresAt":1790000000000}',
      ),
    ]);

    final snapshot = await fetch(http);

    final measure = snapshot.measures.single;
    expect(measure.label, 'Usage');
    expect(measure.used, '40');
    expect(measure.total, '100');
    expect(measure.remaining, '60');
    expect(measure.unit, '%');
    expect(measure.resetsAt, 1790000000000);
  });

  test('parses second-based expiresAt into milliseconds', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"userQuota":{"total":10,"used":5},"expiresAt":1790000000}',
      ),
    ]);

    final snapshot = await fetch(http);

    expect(snapshot.measures.single.resetsAt, 1790000000000);
  });

  test('errors do not expose the PAT or job token', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(statusCode: 401, body: '{}'),
    ]);

    try {
      await fetch(http);
      fail('expected the fetch to fail');
    } on ManagedProviderUsageQueryError catch (error) {
      expect(error.toString(), isNot(contains('pt-test')));
      expect(error.toString(), isNot(contains('jt-test')));
    }
  });
}

const _exchangeOk = ProviderUsageHttpResponse(
  statusCode: 200,
  body: '{"token":"jt-test","refresh_token":"jrt-test","expires_in":86400000}',
);

const _usageOk = ProviderUsageHttpResponse(
  statusCode: 200,
  body: '''
{
  "totalUsagePercentage": 40,
  "isQuotaExceeded": false,
  "expiresAt": 1790000000000,
  "userQuota": {"total": 3000, "used": 1200, "remaining": 1800, "unit": "credits"},
  "addOnQuota": {"total": 50, "used": 50, "remaining": 0, "unit": "credits"},
  "orgResourcePackage": {"cap": 100, "used": 10, "remaining": 90, "unit": "credits"}
}''',
);

class _Scope implements ProviderCredentialScope {
  _Scope(this._values);

  final Map<String, String> _values;

  @override
  bool get isEmpty => _values.isEmpty;

  @override
  Iterable<String> get fields => _values.keys;

  @override
  String? valueFor(String field) => _values[field];
}

class _Credentials implements ProviderCredentialResolver {
  _Credentials(this.values);

  final Map<String, String> values;

  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) async =>
      _Scope(values);
}

class _QueueHttp implements ProviderUsageHttpClient {
  _QueueHttp(this.responses);

  final List<ProviderUsageHttpResponse> responses;
  final requests = <ProviderUsageHttpRequest>[];

  @override
  Future<ProviderUsageHttpResponse> send(
    ProviderUsageHttpRequest request,
  ) async {
    requests.add(request);
    return responses[requests.length - 1];
  }
}
```

Also modify the registry assertion in `client/test/app/app_shell_provider_usage_bootstrap_test.dart`:

```dart
import 'package:teampilot/services/provider_usage/adapters/qoder_usage_adapter.dart';
```

and replace the first test body:

```dart
  test('default registry exposes http-json and qoder adapters', () {
    final registry = buildDefaultManagedProviderUsageRegistry();

    expect(registry.adapterFor('http-json'), isA<HttpJsonMappingAdapter>());
    expect(registry.adapterFor('qoder-usage'), isA<QoderUsageAdapter>());
    expect(registry.adapterFor('codebuddy-credits'), isNull);
    expect(registry.adapterFor('official-claude-subscription'), isNull);
    expect(registry.adapterFor('official-codex-subscription'), isNull);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/provider_usage/qoder_usage_adapter_test.dart \
  test/app/app_shell_provider_usage_bootstrap_test.dart
```

Expected: FAIL — `qoder_usage_adapter.dart` does not exist (compile error), and `QoderUsageAdapter` is undefined in the registry test.

- [ ] **Step 3: Implement the adapter**

Create `client/lib/services/provider_usage/adapters/qoder_usage_adapter.dart`:

```dart
import 'dart:convert';

import '../../../models/managed_provider.dart';
import '../../../models/provider_usage_snapshot.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_subscription_parse.dart';

/// Qoder plan, add-on, and organization credits.
///
/// Qoder PATs cannot authenticate API calls directly. They are exchanged for a
/// short-lived job token, which then authenticates the quota query. The preset
/// URL selects the region, so both requests are derived from that one
/// allowlisted host.
class QoderUsageAdapter implements ManagedProviderUsageAdapter {
  static const adapterId = 'qoder-usage';

  static const _usagePath = '/api/v2/quota/usage';
  static const _exchangePath = '/api/v1/jobToken/exchange';
  static const _allowedHosts = <String>{
    'openapi.qoder.sh',
    'openapi.qoder.com.cn',
  };
  static const _userAgent = 'teampilot-qoder-usage/1.0';
  static const _cosyVersion = '1.0.1';
  static const _cosyClientType = '5';

  @override
  String get id => adapterId;

  @override
  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  }) async {
    final pat = await _readPat(provider, credentials);
    final usageUri = _validatedUsageUri(provider.endpointConfig.url);
    final jobToken = await _exchange(pat, usageUri, http);
    final root = await _fetchUsage(jobToken, usageUri, http);
    final measures = _measures(root, provider);
    if (measures.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
    return ProviderUsageSnapshot(
      providerId: provider.id,
      status: ProviderUsageStatus.ready,
      measures: measures,
      fetchedAt: now.millisecondsSinceEpoch,
    );
  }

  static Future<String> _readPat(
    ManagedProvider provider,
    ProviderCredentialResolver resolver,
  ) async {
    ProviderCredentialScope? scope;
    try {
      scope = await resolver.resolve(provider);
    } on Object {
      scope = null;
    }
    final value = scope?.valueFor('apiKey')?.trim() ?? '';
    if (value.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    return value;
  }

  static Uri _validatedUsageUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        !_allowedHosts.contains(uri.host.toLowerCase()) ||
        uri.path != _usagePath ||
        uri.hasPort && uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }
    return uri;
  }

  static Future<String> _exchange(
    String pat,
    Uri usageUri,
    ProviderUsageHttpClient http,
  ) async {
    final response = await _send(
      http,
      ProviderUsageHttpRequest(
        method: 'POST',
        uri: usageUri.replace(path: _exchangePath, query: '', fragment: ''),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
          'user-agent': _userAgent,
          'cosy-version': _cosyVersion,
          'cosy-clienttype': _cosyClientType,
        },
        body: jsonEncode({'personal_token': pat}),
      ),
    );
    if (response.statusCode == 400 ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.authenticationFailed,
      );
    }
    throwOfficialHttpStatus(response.statusCode);
    final token = decodeOfficialJsonObject(response.body)['token'];
    if (token is! String || token.trim().isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
    return token.trim();
  }

  static Future<Map<String, Object?>> _fetchUsage(
    String jobToken,
    Uri usageUri,
    ProviderUsageHttpClient http,
  ) async {
    final response = await _send(
      http,
      ProviderUsageHttpRequest(
        method: 'GET',
        uri: usageUri,
        headers: {
          'authorization': 'Bearer $jobToken',
          'accept': 'application/json',
          'user-agent': _userAgent,
        },
      ),
    );
    throwOfficialHttpStatus(response.statusCode);
    return decodeOfficialJsonObject(response.body);
  }

  static Future<ProviderUsageHttpResponse> _send(
    ProviderUsageHttpClient http,
    ProviderUsageHttpRequest request,
  ) async {
    try {
      return await http.send(request);
    } on ManagedProviderUsageQueryError {
      rethrow;
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.networkFailed,
      );
    }
  }

  static List<ProviderUsageMeasure> _measures(
    Map<String, Object?> root,
    ManagedProvider provider,
  ) {
    final resetsAt = parseOfficialResetAt(root['expiresAt']);
    final measures = <ProviderUsageMeasure>[];

    void addBucket(String label, Object? raw, {required String totalKey}) {
      final bucket = _asMap(raw);
      if (bucket == null || !_hasQuotaNumber(bucket, totalKey: totalKey)) {
        return;
      }
      measures.add(
        ProviderUsageMeasure(
          label: label,
          kind: ProviderUsageMeasureKind.quota,
          used: _decimal(bucket['used']),
          total: _decimal(bucket[totalKey]),
          remaining: _decimal(bucket['remaining']),
          unit: _unit(bucket['unit'], provider),
          resetsAt: resetsAt,
        ),
      );
    }

    addBucket('Plan', root['userQuota'], totalKey: 'total');
    addBucket('Add-on', root['addOnQuota'], totalKey: 'total');
    final org = _asMap(root['orgResourcePackage']);
    final orgTotalKey = org != null && _finiteNonNegative(org['cap']) != null
        ? 'cap'
        : 'total';
    addBucket('Org', org, totalKey: orgTotalKey);
    if (measures.isNotEmpty) return measures;

    final percentage = _finiteNonNegative(root['totalUsagePercentage']);
    if (percentage == null) return const [];
    final clamped = percentage.clamp(0, 100).toDouble();
    return [
      ProviderUsageMeasure(
        label: 'Usage',
        kind: ProviderUsageMeasureKind.quota,
        used: _decimal(clamped),
        total: '100',
        remaining: _decimal(100 - clamped),
        unit: '%',
        resetsAt: resetsAt,
      ),
    ];
  }

  static bool _hasQuotaNumber(
    Map<String, Object?> bucket, {
    required String totalKey,
  }) => _finiteNonNegative(bucket['used']) != null ||
      _finiteNonNegative(bucket['remaining']) != null ||
      _finiteNonNegative(bucket[totalKey]) != null;

  static Map<String, Object?>? _asMap(Object? raw) {
    if (raw is! Map) return null;
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  static num? _finiteNonNegative(Object? raw) {
    final value = raw is num
        ? raw
        : raw is String
        ? num.tryParse(raw.trim())
        : null;
    if (value == null || !value.isFinite || value < 0) return null;
    return value;
  }

  static String? _decimal(Object? raw) {
    final value = _finiteNonNegative(raw);
    if (value == null) return null;
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  static String? _unit(Object? raw, ManagedProvider provider) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    final configured = provider.displayConfig.unit?.trim() ?? '';
    return configured.isEmpty ? 'credits' : configured;
  }
}
```

Wire it into `client/lib/app/app_shell.dart`:

```dart
import '../services/provider_usage/adapters/qoder_usage_adapter.dart';
```

and:

```dart
  return ManagedProviderUsageRegistry([
    HttpJsonMappingAdapter(cliCredentials: cliCredentials),
    if (fs != null && basePath != null)
      CodebuddyCreditsUsageAdapter(fs: fs, basePath: basePath),
    QoderUsageAdapter(),
  ]);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/provider_usage/qoder_usage_adapter_test.dart \
  test/app/app_shell_provider_usage_bootstrap_test.dart
```

Expected: PASS for both files.

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/services/provider_usage/adapters/qoder_usage_adapter.dart \
  client/test/services/provider_usage/qoder_usage_adapter_test.dart \
  client/lib/app/app_shell.dart \
  client/test/app/app_shell_provider_usage_bootstrap_test.dart
git commit -m "feat(provider-usage): add Qoder PAT-backed usage adapter"
```

---

### Task 2: Qoder presets and editor schema

**Files:**
- Modify: `client/lib/services/provider_usage/managed_provider_presets.dart:30-156` (schema helpers), `:156-397` (preset list)
- Modify: `client/test/services/provider_usage/managed_provider_presets_test.dart:7-15`, `:116-126`

**Interfaces:**
- Consumes: `ManagedProviderPreset`, `ManagedProviderEditorSchema`, `ManagedProviderEditorField`, `ManagedProviderEditorFieldKind`, `ManagedProviderEditorSection`, `ManagedProvider`, `ManagedProviderEndpointConfig`, `ManagedProviderDisplayConfig`.
- Produces: presets with ids `qoder` and `qoder-cn`, both `adapterId: 'qoder-usage'`, `kind: subscriptionQuota`, `endpointConfig.credentialField: 'apiKey'`.

- [ ] **Step 1: Write the failing preset tests**

In `client/test/services/provider_usage/managed_provider_presets_test.dart`, add `'qoder', 'qoder-cn'` after `'opencode-go'` in both hardcoded id lists (the `built-in presets expose stable provider templates` test and the `quick preset options include built-ins and custom` test).

Add this test before `lookup returns null for unknown preset ids`:

```dart
  test('Qoder presets are PAT-backed and region-specific', () {
    final global = managedProviderPresetById('qoder')!;
    expect(global.template.name, 'Qoder');
    expect(global.template.kind, ManagedProviderKind.subscriptionQuota);
    expect(global.template.adapterId, 'qoder-usage');
    expect(
      global.template.endpointConfig.url,
      'https://openapi.qoder.sh/api/v2/quota/usage',
    );
    expect(global.template.endpointConfig.method, 'GET');
    expect(global.template.endpointConfig.credentialField, 'apiKey');
    expect(global.template.endpointConfig.credentialSource, 'secret');
    expect(global.template.displayConfig.unit, 'credits');
    expect(global.schema?.isFieldEditable('endpointConfig.url'), isTrue);
    expect(global.schema?.isFieldEditable('apiKey'), isTrue);
    expect(global.schema?.hasField('endpointConfig.windows'), isFalse);

    final cn = managedProviderPresetById('qoder-cn')!;
    expect(cn.template.name, 'Qoder CN');
    expect(
      cn.template.endpointConfig.url,
      'https://openapi.qoder.com.cn/api/v2/quota/usage',
    );
    expect(cn.template.adapterId, 'qoder-usage');
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/provider_usage/managed_provider_presets_test.dart
```

Expected: FAIL — the id lists lack `qoder`/`qoder-cn` and `managedProviderPresetById('qoder')` returns null.

- [ ] **Step 3: Implement the presets and schema**

In `client/lib/services/provider_usage/managed_provider_presets.dart`, add these top-level helpers after `_deepSeekEditorSchema`:

```dart
ManagedProviderEditorSchema _qoderEditorSchema({
  required String name,
  required String url,
}) => ManagedProviderEditorSchema(
  sections: const {
    ManagedProviderEditorSection.basics,
    ManagedProviderEditorSection.query,
    ManagedProviderEditorSection.credentials,
    ManagedProviderEditorSection.display,
    ManagedProviderEditorSection.advanced,
  },
  fields: [
    ManagedProviderEditorField(
      key: 'name',
      kind: ManagedProviderEditorFieldKind.text,
      required: true,
      defaultValue: name,
    ),
    const ManagedProviderEditorField(
      key: 'kind',
      kind: ManagedProviderEditorFieldKind.text,
      required: true,
      defaultValue: 'subscriptionQuota',
      readOnly: true,
    ),
    const ManagedProviderEditorField(
      key: 'adapterId',
      kind: ManagedProviderEditorFieldKind.text,
      required: true,
      defaultValue: 'qoder-usage',
      readOnly: true,
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.url',
      kind: ManagedProviderEditorFieldKind.url,
      required: true,
      defaultValue: url,
    ),
    const ManagedProviderEditorField(
      key: 'endpointConfig.method',
      kind: ManagedProviderEditorFieldKind.text,
      required: true,
      defaultValue: 'GET',
      readOnly: true,
    ),
    const ManagedProviderEditorField(
      key: 'apiKey',
      kind: ManagedProviderEditorFieldKind.secret,
      required: true,
    ),
    const ManagedProviderEditorField(
      key: 'displayConfig.unit',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: 'credits',
    ),
    const ManagedProviderEditorField(
      key: 'displayConfig.decimalPlaces',
      kind: ManagedProviderEditorFieldKind.integer,
      required: false,
      defaultValue: '2',
    ),
    const ManagedProviderEditorField(
      key: 'displayConfig.showPercent',
      kind: ManagedProviderEditorFieldKind.toggle,
      required: false,
      defaultValue: 'false',
    ),
    const ManagedProviderEditorField(
      key: 'enabled',
      kind: ManagedProviderEditorFieldKind.toggle,
      required: false,
      defaultValue: 'true',
    ),
  ],
  firstQuery: true,
);

ManagedProviderPreset _qoderPreset({
  required String id,
  required String name,
  required String url,
}) => ManagedProviderPreset(
  id: id,
  labelId: id,
  hintId: id,
  template: ManagedProvider(
    id: '',
    name: name,
    kind: ManagedProviderKind.subscriptionQuota,
    adapterId: 'qoder-usage',
    endpointConfig: ManagedProviderEndpointConfig(
      url: url,
      method: 'GET',
      credentialField: 'apiKey',
    ),
    displayConfig: ManagedProviderDisplayConfig(
      unit: 'credits',
      decimalPlaces: 2,
    ),
  ),
  schema: _qoderEditorSchema(name: name, url: url),
);
```

Then append two entries to the `builtInManagedProviderPresets` list, after the `opencode-go` preset entry:

```dart
      _qoderPreset(
        id: 'qoder',
        name: 'Qoder',
        url: 'https://openapi.qoder.sh/api/v2/quota/usage',
      ),
      _qoderPreset(
        id: 'qoder-cn',
        name: 'Qoder CN',
        url: 'https://openapi.qoder.com.cn/api/v2/quota/usage',
      ),
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/provider_usage/managed_provider_presets_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/services/provider_usage/managed_provider_presets.dart \
  client/test/services/provider_usage/managed_provider_presets_test.dart
git commit -m "feat(provider-usage): add Qoder usage presets"
```

---

### Task 3: Localized preset labels and hints

**Files:**
- Modify: `client/lib/i18n/managedProviders_en.i18n.json:124-126`
- Modify: `client/lib/i18n/managedProviders_zh.i18n.json:124-126`
- Modify: `client/lib/l10n/l10n_extensions.dart:60-81`
- Generated: `client/lib/l10n/translations_en.g.dart`, `client/lib/l10n/translations_zh.g.dart`
- Modify: `client/test/services/provider_usage/managed_provider_presets_test.dart` (imports + l10n test)

**Interfaces:**
- Consumes: `managedProviderQuickPresetOptionIds`, `managedProviderPresetLabel`, `managedProviderPresetHint`, `AppLocalizationsEn`.
- Produces: non-empty label and hint for every quick preset id, including `qoder` and `qoder-cn`.

- [ ] **Step 1: Write the failing l10n test**

In `client/test/services/provider_usage/managed_provider_presets_test.dart`, add:

```dart
import 'package:teampilot/l10n/l10n_extensions.dart';
```

and add this test:

```dart
  test('every quick preset id has an English label and hint', () {
    final l10n = AppLocalizationsEn();
    for (final id in managedProviderQuickPresetOptionIds) {
      expect(l10n.managedProviderPresetLabel(id), isNotEmpty, reason: id);
      expect(l10n.managedProviderPresetHint(id), isNotEmpty, reason: id);
    }
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/provider_usage/managed_provider_presets_test.dart
```

Expected: FAIL — `managedProviderPresetHint('qoder')` and `('qoder-cn')` return an empty string.

- [ ] **Step 3: Add the strings and mappings**

In `client/lib/i18n/managedProviders_en.i18n.json`, after `"quickPresetOpencodeGoHint"`:

```json
  "quickPresetQoder": "Qoder",
  "quickPresetQoderCn": "Qoder CN",
  "quickPresetQoderCnHint": "Query plan credits with a PAT from qoder.com.cn/account/integrations.",
  "quickPresetQoderHint": "Query plan credits with a PAT from qoder.com/account/integrations.",
```

In `client/lib/i18n/managedProviders_zh.i18n.json`, after `"quickPresetOpencodeGoHint"`:

```json
  "quickPresetQoder": "Qoder",
  "quickPresetQoderCn": "Qoder CN",
  "quickPresetQoderCnHint": "使用 qoder.com.cn/account/integrations 生成的 PAT 查询套餐积分。",
  "quickPresetQoderHint": "使用 qoder.com/account/integrations 生成的 PAT 查询套餐积分。",
```

In `client/lib/l10n/l10n_extensions.dart`, add to `managedProviderPresetLabel`:

```dart
    'qoder' => managedProviders.quickPresetQoder,
    'qoder-cn' => managedProviders.quickPresetQoderCn,
```

and to `managedProviderPresetHint`:

```dart
    'qoder' => managedProviders.quickPresetQoderHint,
    'qoder-cn' => managedProviders.quickPresetQoderCnHint,
```

Regenerate:

```bash
cd client && dart run slang
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/provider_usage/managed_provider_presets_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/i18n/managedProviders_en.i18n.json \
  client/lib/i18n/managedProviders_zh.i18n.json \
  client/lib/l10n/l10n_extensions.dart \
  client/lib/l10n/translations_en.g.dart \
  client/lib/l10n/translations_zh.g.dart \
  client/test/services/provider_usage/managed_provider_presets_test.dart
git commit -m "feat(l10n): label Qoder usage presets"
```

---

### Task 4: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no errors or warnings from the new files.

- [ ] **Step 2: Run the focused tests**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/provider_usage/qoder_usage_adapter_test.dart \
  test/services/provider_usage/managed_provider_presets_test.dart \
  test/app/app_shell_provider_usage_bootstrap_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run the full suite once**

Run in the background:

```bash
cd client && dart run tool/run_tests.dart
```

Expected: PASS. Do not use `flutter test`.

- [ ] **Step 4: Report**

Report the analyze result, the three focused test files, and the full-suite result. If the full suite has unrelated failures, list them with file names and do not claim completion.
