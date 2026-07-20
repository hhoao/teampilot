import '../../../agent_status/member_agent_status_endpoint.dart';

const _agentStatusHookEvents = [
  'PermissionRequest',
  'PreToolUse',
  'PostToolUse',
  'Stop',
  'UserPromptSubmit',
];

/// Install HTTP hooks that POST seat lifecycle events to `/agent-status`
/// (permission attention + idle/done). Headers via [endpoint.headersFor].
///
/// Idempotent for the same URL. Install for simple and team seats whenever
/// [endpoint] is non-null — not gated on mixed mode.
Map<String, Object?> mergeAgentStatusHooks(
  Map<String, Object?> settings,
  String memberId,
  MemberAgentStatusEndpoint endpoint,
) {
  final hooks = Map<String, Object?>.from(
    (settings['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
  );
  final headers = endpoint.headersFor(memberId);
  for (final event in _agentStatusHookEvents) {
    final entries = List<Object?>.from((hooks[event] as List?) ?? const []);
    final exists = entries.any(
      (e) =>
          e is Map &&
          (e['hooks'] as List?)?.any(
                (h) => h is Map && h['url'] == endpoint.url,
              ) ==
              true,
    );
    if (!exists) {
      entries.add({
        'hooks': [
          {'type': 'http', 'url': endpoint.url, 'headers': headers},
        ],
      });
    }
    hooks[event] = entries;
  }
  return {...settings, 'hooks': hooks};
}
