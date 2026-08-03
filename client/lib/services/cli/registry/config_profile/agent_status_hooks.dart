import '../../../agent_status/member_agent_status_endpoint.dart';

const _agentStatusHookEvents = [
  'PermissionRequest',
  'PreToolUse',
  'PostToolUse',
  'PostToolUseFailure',
  'Stop',
  'StopFailure',
  'UserPromptSubmit',
];

/// Tool-lifecycle events that accept a matcher (Orca uses `*`).
const _agentStatusMatcherEvents = {
  'PermissionRequest',
  'PreToolUse',
  'PostToolUse',
  'PostToolUseFailure',
};

/// Install HTTP hooks that POST seat lifecycle events to `/agent-status`
/// (permission attention + idle/done). Headers via [endpoint.headersFor].
///
/// Each event gets a distinct URL (`?event=<name>`) so Claude's HTTP-hook
/// dedupe-by-URL cannot collapse PermissionRequest with PostToolUse/Stop —
/// that left waiting sticky after the turn finished.
///
/// Idempotent for the same event URL. Install for simple and team seats
/// whenever [endpoint] is non-null — not gated on mixed mode.
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
    final eventUrl = agentStatusHookUrl(endpoint.url, event);
    final entries = List<Object?>.from((hooks[event] as List?) ?? const []);
    final exists = entries.any(
      (e) =>
          e is Map &&
          (e['hooks'] as List?)?.any(
                (h) => h is Map && h['url'] == eventUrl,
              ) ==
              true,
    );
    if (!exists) {
      final hook = <String, Object?>{
        'type': 'http',
        'url': eventUrl,
        'headers': headers,
        // AskUserQuestion PreToolUse holds this HTTP call until the chat card
        // answers (updatedInput.answers). Other events return immediately.
        'timeout': event == 'PreToolUse' ? 86400 : 5,
      };
      final entry = <String, Object?>{
        'hooks': [hook],
      };
      if (_agentStatusMatcherEvents.contains(event)) {
        entry['matcher'] = '*';
      }
      entries.add(entry);
    } else {
      // Refresh timeout / headers on existing status hooks (idempotent merge
      // used to skip updates and leave AskUserQuestion stuck at timeout: 5).
      for (final e in entries) {
        if (e is! Map) continue;
        final eventHooks = e['hooks'];
        if (eventHooks is! List) continue;
        for (final h in eventHooks) {
          if (h is! Map || h['url'] != eventUrl) continue;
          h['timeout'] = event == 'PreToolUse' ? 86400 : 5;
          h['headers'] = headers;
        }
      }
    }
    hooks[event] = entries;
  }
  return {...settings, 'hooks': hooks};
}

/// Per-event status URL so identical-handler dedupe keeps every lifecycle hook.
String agentStatusHookUrl(String baseUrl, String eventName) {
  final uri = Uri.parse(baseUrl);
  final next = Map<String, String>.from(uri.queryParameters)
    ..['event'] = eventName;
  return uri.replace(queryParameters: next).toString();
}
