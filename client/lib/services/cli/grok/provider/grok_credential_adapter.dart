import 'dart:convert';
import 'dart:io' show File, Platform, Process;

import '../../../../models/credential_lease.dart';
import '../../../../services/cli/registry/capabilities/provider_capability.dart';
import '../../../../services/cli/registry/capabilities/session_credential_capability.dart';
import '../../../../services/io/filesystem.dart';
import '../../../../services/provider/credential_lease_endpoint.dart';
import '../../../../services/provider/oauth_credential_authority.dart';
import '../../../../utils/logging/logger_utils.dart';
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
    bool? isWindows,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _isWindows = isWindows ?? Platform.isWindows;

  final OAuthCredentialAuthority authority;

  /// Maps a session id to the provider id it was launched with; null means
  /// "unknown session" and skips the provider-identity check.
  final String? Function(String sessionId) sessionProviderId;
  final DateTime Function() _now;
  final bool _isWindows;

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
    // The shim is POSIX sh only. Fail fast only for a LOCAL Windows seat; a
    // Windows host driving a POSIX work plane over SSH must not be blocked —
    // the shim runs on the remote work plane, not on the host OS.
    if (!ctx.crossMachine && _isWindows) {
      AppLogger.instance.w(
        'grok external auth provider unsupported on local windows',
      );
      throw const CredentialUnavailableException(CredentialHealth.missing);
    }
    // A custom (non-'xai') providerId is legitimate. The production
    // sessionProviderId resolver is currently fixed to 'xai', so an equality
    // rejection here would refuse every custom-provider seat. Keep it as a
    // diagnostic only.
    final allowed = sessionProviderId(ctx.sessionId);
    if (allowed != null && allowed != providerId) {
      AppLogger.instance.d(
        'grok external auth provider: seat provider $providerId differs from '
        'resolved session provider $allowed',
      );
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

    // No reachable control-plane endpoint (neither an agent-status nor an idle
    // binding): fail before spawning an agent that could never authenticate.
    final endpoint = _endpointFor(ctx);
    if (endpoint.isEmpty) {
      throw const CredentialUnavailableException(CredentialHealth.missing);
    }

    final configDir = ctx.paths.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      GrokConstants.executableName,
      // Must match GrokProviderCapability's session-home dir, otherwise
      // `GROK_HOME` (this adapter) and config.toml (the provider capability)
      // would land in different member trees.
      memberId: ctx.memberId ?? ctx.scope.memberId,
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
    // Best effort locally; a remote flush does not preserve the mode, which is
    // why the injected command below runs the shim through `sh`.
    _restrict(fs, shimPath, executable: true);

    final leaseConfigPath = fs.pathContext.join(
      configDir,
      GrokConstants.leaseConfigFileName,
    );
    final memberId =
        ctx.memberId ?? ctx.scope.memberId ?? ctx.member?.id ?? 'acp';
    final sessionId =
        ctx.agentStatus?.sessionId ?? ctx.busIdle?.sessionId ?? ctx.sessionId;
    // A local seat's token is the session id, which the gateway treats as
    // "no token"; a remote seat carries its real tunnel token here.
    final busToken =
        ctx.agentStatus?.token ?? ctx.busIdle?.token ?? ctx.sessionId;
    final body = <String, Object?>{
      'providerId': providerId,
      'endpoint': endpoint,
      'sessionId': sessionId,
      'memberId': memberId,
      'busToken': busToken,
    };
    await fs.atomicWrite(leaseConfigPath, jsonEncode(body));
    _restrict(fs, leaseConfigPath);

    return SessionHomeContribution(
      environment: {
        GrokConstants.homeEnvKey: configDir,
        GrokConstants.authProviderCommandEnvKey: _shCommand(shimPath),
      },
    );
  }

  /// Prefer the agent-status endpoint: every seat gets one (native / simple /
  /// mixed, local or SSH), while the idle endpoint only exists for mixed teams.
  /// Both expose the same loopback shape (`MemberAgentStatusEndpoint.local`
  /// and `MemberBusIdleEndpoint.local` share the gateway port), so the lease
  /// path can be appended either way.
  String _endpointFor(SessionHomeContext ctx) {
    final url = ctx.agentStatus?.url ?? ctx.busIdle?.url ?? '';
    if (url.isEmpty) return '';
    final base = _baseOf(url);
    if (base.isEmpty) return '';
    return '$base${CredentialLeaseEndpoint.path}';
  }

  /// grok runs the env var through `sh -c`. Quoting the path keeps paths with
  /// spaces or quotes intact and removes the dependency on an executable bit,
  /// which a remote (SSH) flush does not preserve.
  static String _shCommand(String path) =>
      "sh '${path.replaceAll("'", r"'\''")}'";

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
# curl -w appends "\n<http_status>" so a transient 503 (retry) and a 409
# (needs sign-in) can be told apart on stderr. grok only reads stdout.
RESP=$(curl -sS --max-time "$TIMEOUT" \
  -w '\n%{http_code}' \
  -H "Content-Type: application/json" \
  -H "X-Session: $SESSION" \
  -H "X-Bus-Token: $TOKEN" \
  -X POST -d "$BODY" "$ENDPOINT") || { echo "lease request failed" >&2; exit 1; }

STATUS=$(printf '%s' "$RESP" | tail -n 1)
BODY_RESP=$(printf '%s' "$RESP" | sed '$d')

ACCESS=$(printf '%s' "$BODY_RESP" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
if [ -z "$ACCESS" ]; then
  case "$STATUS" in
    503) echo "credential service temporarily unavailable, please retry later" >&2 ;;
    409|401) echo "credentials rejected, please sign in again" >&2 ;;
    *) echo "lease rejected (HTTP $STATUS)" >&2 ;;
  esac
  exit 1
fi

EXPIRES=$(printf '%s' "$BODY_RESP" | sed -n 's/.*"expires_in"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9]\{1,\}\).*/\1/p' | head -1)
[ -n "$EXPIRES" ] || EXPIRES=3600

printf '{"access_token":"%s","expires_in":%s}\n' "$ACCESS" "$EXPIRES"
''';
