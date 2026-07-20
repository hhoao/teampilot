import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../cubits/agent_attention_cubit.dart';
import '../../models/team_config.dart';
import 'agent_status_normalizer.dart';

/// Max POST body size for `/agent-status` (~1 MiB).
const int agentStatusMaxBodyBytes = 1024 * 1024;

/// Parses CLI hook JSON → [AgentStatusNormalizer] → [AgentAttentionCubit].
///
/// Never touches TeamBus idle / park. Corrupt or oversized bodies keep prior
/// attention and return HTTP 200 `{}`.
class AgentStatusHttpHandler {
  AgentStatusHttpHandler({
    required this.attention,
    required this.resolveCli,
    required this.resolveSkipPermissions,
  });

  final AgentAttentionCubit attention;
  final CliTool Function(String sessionId, String memberId) resolveCli;
  final bool Function(String sessionId, String memberId) resolveSkipPermissions;

  Future<void> handle(
    HttpRequest request, {
    required String sessionId,
    required String memberId,
  }) async {
    try {
      final body = await _readJsonBody(request);
      if (body != null) {
        final event = AgentStatusNormalizer.normalize(
          cli: resolveCli(sessionId, memberId),
          body: body,
        );
        if (event != null) {
          attention.applyEvent(
            sessionId: sessionId,
            memberId: memberId,
            event: event,
            skipPermissions: resolveSkipPermissions(sessionId, memberId),
          );
        }
      }
      await _writeOkEmpty(request);
    } catch (_) {
      try {
        await _writeOkEmpty(request);
      } catch (_) {}
    }
  }

  Future<Map<String, Object?>?> _readJsonBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    var overflow = false;
    await for (final chunk in request) {
      if (overflow) continue;
      builder.add(chunk);
      if (builder.length > agentStatusMaxBodyBytes) {
        overflow = true;
        builder.clear();
      }
    }
    if (overflow) return null;

    final bytes = builder.takeBytes();
    if (bytes.isEmpty) return null;

    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeOkEmpty(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      )
      ..write('{}');
    await request.response.close();
  }
}
