import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_session.dart';
import 'team_generation_job_store.dart';

/// Lookup seam so the authorizer can verify the persisted builder session
/// without depending on repositories.
abstract interface class TeamGenerationSessionLookup {
  Future<AppSession?> findById(String sessionId);
}

/// Principal extracted from an MCP transport request.
final class TeamGenerationPrincipal {
  const TeamGenerationPrincipal({
    required this.sessionId,
    required this.workspaceId,
    required this.workflowId,
  });

  final String sessionId;
  final String workspaceId;
  final String workflowId;
}

/// Issues/authorizes/revokes one ephemeral workflow token per builder
/// session. Only a SHA-256 digest is retained in memory — never the raw
/// token, and never anything inside `job.json`.
final class TeamGenerationAuthorizer {
  TeamGenerationAuthorizer({
    required TeamGenerationSessionLookup sessionLookup,
    required TeamGenerationJobStore jobStore,
    String Function()? tokenFactory,
  }) : _sessionLookup = sessionLookup,
       _jobStore = jobStore,
       _tokenFactory = tokenFactory ?? _defaultTokenFactory;

  final TeamGenerationSessionLookup _sessionLookup;
  final TeamGenerationJobStore _jobStore;
  final String Function() _tokenFactory;

  /// workflowId -> SHA-256 hex digest of the current live token.
  final _digests = <String, String>{};

  static String _defaultTokenFactory() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${const Uuid().v4()}';

  /// Issues a token synchronously for the launch connector. Authorization is
  /// still checked asynchronously on every Composer request.
  String issueForSession(TeamGenerationPrincipal principal) {
    final token = _tokenFactory();
    _digests[principal.workflowId] = _digestOf(token);
    return token;
  }

  /// Rotates the workflow token and verifies the persisted builder binding.
  Future<String> issue(TeamGenerationPrincipal principal) async {
    final token = issueForSession(principal);
    try {
      final authorized = await authorize(principal: principal, token: token);
      if (!authorized) {
        throw StateError(
          'cannot issue team-generation token for '
          '${principal.sessionId}/${principal.workflowId}',
        );
      }
    } on Object {
      _digests.remove(principal.workflowId);
      rethrow;
    }
    return token;
  }

  Future<bool> authorize({
    required TeamGenerationPrincipal principal,
    required String token,
  }) async {
    if (token.trim().isEmpty) return false;
    final expected = _digests[principal.workflowId];
    if (expected == null || expected != _digestOf(token)) return false;

    final job = await _jobStore.read(
      principal.workspaceId,
      principal.workflowId,
    );
    if (job == null || !job.isActive) return false;
    if (job.builderSessionId != principal.sessionId) return false;
    if (job.workspaceId != principal.workspaceId) return false;

    final session = await _sessionLookup.findById(principal.sessionId);
    if (session == null) return false;
    if (session.purpose != SessionPurpose.teamGeneration) return false;
    if (session.workflowId != principal.workflowId) return false;
    if (session.workspaceId != principal.workspaceId) return false;
    return true;
  }

  /// Called on cancel/completion and before restart re-issue.
  void revoke(String workflowId) => _digests.remove(workflowId);

  String _digestOf(String token) => sha256.convert(utf8.encode(token)).toString();
}
