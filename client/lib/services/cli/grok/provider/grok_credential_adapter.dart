import 'dart:convert';
import 'dart:io' show File, Platform, Process;

import '../../../../models/credential_lease.dart';
import '../../../../services/cli/registry/capabilities/provider_capability.dart';
import '../../../../services/cli/registry/capabilities/session_credential_capability.dart';
import '../../../../services/io/filesystem.dart';
import '../../../../services/provider/credential_lease_endpoint.dart';
import '../../../../services/provider/oauth_credential_authority.dart';
import '../grok_constants.dart';

/// Grok implementation of [SessionCredentialCapability].
///
/// Injects grok's official External Auth Provider command into the isolated
/// `GROK_HOME`. The shim POSTs to the control-plane lease endpoint; grok
/// re-runs it on a missing credential, near-expiry rotation, and 401.
final class GrokCredentialAdapter implements SessionCredentialCapability {
  GrokCredentialAdapter({
    required this.authority,
    required this.sessionProviderId,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final OAuthCredentialAuthority authority;

  /// Maps a session id to the provider id it was launched with; null means
  /// "unknown session" and skips the provider-identity check.
  final String? Function(String sessionId) sessionProviderId;
  final DateTime Function() _now;

  @override
  Future<CredentialLease> leaseCredentials({
    required String providerId,
    required String sessionId,
    bool forceRefresh = false,
  }) => authority.lease(
    providerId: providerId,
    sessionId: sessionId,
    forceRefresh: forceRefresh,
  );

  @override
  Future<CredentialHealth> credentialStatus(String providerId) =>
      authority.status(providerId);

  @override
  Future<bool> onAuthRequired({
    required String providerId,
    required String sessionId,
  }) => authority.recover(providerId, sessionId);

  /// Launch-time materialization. Fails before the agent is spawned when the
  /// provider needs a login (pre-launch credential gate).
  Future<SessionHomeContribution> materialize(
    SessionHomeContext ctx, {
    required String providerId,
  }) async {
    // A seat may only request the provider it was launched with.
    final allowed = sessionProviderId(ctx.sessionId);
    if (allowed != null && allowed != providerId) {
      throw const CredentialUnavailableException(CredentialHealth.missing);
    }
    // Force one lease up front so a dead credential surfaces here, not as a
    // confusing mid-session "not logged in".
    final lease = await leaseCredentials(
      providerId: providerId,
      sessionId: ctx.sessionId,
    );
    if (lease.expiresInSeconds(_now()) <= 0) {
      throw const CredentialUnavailableException(CredentialHealth.expiring);
    }

    // No reachable lease endpoint (missing idle binding): fail before spawning
    // an agent that could never authenticate.
    final endpoint = _endpointFor(ctx);
    if (endpoint.isEmpty) {
      throw const CredentialUnavailableException(CredentialHealth.missing);
    }

    final configDir = ctx.paths.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      GrokConstants.executableName,
      memberId: ctx.memberId,
    );
    final fs = ctx.paths.fs;
    await fs.ensureDir(configDir);

    final binDir = fs.pathContext.join(configDir, 'bin');
    await fs.ensureDir(binDir);
    final shimPath = fs.pathContext.join(
      binDir,
      GrokConstants.leaseShimFileName,
    );
    await fs.atomicWrite(shimPath, _shimScript);
    // grok runs the command via `sh -c`, so the shim needs the executable bit.
    _restrict(fs, shimPath, executable: true);

    final leaseConfigPath = fs.pathContext.join(
      configDir,
      GrokConstants.leaseConfigFileName,
    );
    final memberId = ctx.memberId ?? ctx.member?.id ?? 'acp';
    final busIdle = ctx.busIdle;
    final body = <String, Object?>{
      'providerId': providerId,
      'endpoint': endpoint,
      'sessionId': ctx.sessionId,
      'memberId': memberId,
      // A local seat's bus token is the session id, which the gateway treats
      // as "no token"; a remote seat carries its real tunnel token here.
      'busToken': busIdle?.token ?? ctx.sessionId,
    };
    await fs.atomicWrite(leaseConfigPath, jsonEncode(body));
    _restrict(fs, leaseConfigPath);

    return SessionHomeContribution(
      environment: {
        GrokConstants.homeEnvKey: configDir,
        GrokConstants.authProviderCommandEnvKey: shimPath,
      },
    );
  }

  /// Local seats use the in-process gateway loopback (`MemberBusIdleEndpoint
  /// .local`); remote seats reuse the already-provisioned idle HTTP tunnel
  /// port (`.remote`). No gateway port needs to be injected at construction,
  /// so the adapter can be built before the gateway exists.
  String _endpointFor(SessionHomeContext ctx) {
    final url = ctx.busIdle?.url ?? '';
    if (url.isEmpty) return '';
    final base = _baseOf(url);
    if (base.isEmpty) return '';
    return '$base${CredentialLeaseEndpoint.path}';
  }

  static String _baseOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return '';
    return '${uri.scheme}://${uri.host}:${uri.port}';
  }

  static void _restrict(Filesystem fs, String path, {bool executable = false}) {
    if (Platform.isWindows) return;
    try {
      if (!File(path).existsSync()) return;
      Process.runSync('chmod', [executable ? '700' : '600', path]);
    } on Object {
      // Best effort: OverlayFilesystem / InMemoryFilesystem have no real
      // POSIX path. Tests exercise content, not permissions.
    }
  }
}

/// POSIX sh shim. grok's External Auth Provider contract reads stdout only, so
/// stdout carries exactly `{"access_token": ..., "expires_in": ...}`; the
/// control-plane response's extra `epoch` field is stripped rather than
/// forwarded. `GROK_AUTH_EXPIRED=1` means a silent headless refresh — fail fast.
const String _shimScript = r'''#!/bin/sh
# Generated by TeamPilot. Do not edit.
# POSTs to the control-plane /credentials/lease endpoint and prints only the
# {"access_token":...,"expires_in":...} contract on stdout.
set -u
CFG="$(dirname "$0")/../credential-lease.json"
[ -f "$CFG" ] || { echo "missing lease config" >&2; exit 1; }

ENDPOINT=$(sed -n 's/.*"endpoint"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" | head -1)
PROVIDER=$(sed -n 's/.*"providerId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" | head -1)
SESSION=$(sed -n 's/.*"sessionId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" | head -1)
TOKEN=$(sed -n 's/.*"busToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" | head -1)

[ -n "$ENDPOINT" ] || { echo "missing endpoint" >&2; exit 1; }

if [ "${GROK_AUTH_EXPIRED:-}" = "1" ]; then
  TIMEOUT=3
else
  TIMEOUT=10
fi

BODY="{\"providerId\":\"$PROVIDER\",\"forceRefresh\":false}"
RESP=$(curl -sS --max-time "$TIMEOUT" \
  -H "Content-Type: application/json" \
  -H "X-Session: $SESSION" \
  -H "X-Bus-Token: $TOKEN" \
  -X POST -d "$BODY" "$ENDPOINT") || { echo "lease request failed" >&2; exit 1; }

ACCESS=$(printf '%s' "$RESP" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$ACCESS" ] || { echo "lease rejected: $RESP" >&2; exit 1; }

EXPIRES=$(printf '%s' "$RESP" | sed -n 's/.*"expires_in"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9]\{1,\}\).*/\1/p' | head -1)
[ -n "$EXPIRES" ] || EXPIRES=3600

printf '{"access_token":"%s","expires_in":%s}\n' "$ACCESS" "$EXPIRES"
''';
