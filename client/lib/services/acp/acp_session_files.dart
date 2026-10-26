/// File names of the app-owned ACP sidecars under `sessions/<id>/runtime/`.
///
/// Personal sessions use a single seat; mixed seats get one file per roster
/// member so parallel agents never share a transcript / agent-session id.
library;

/// Transcript snapshot of the folded chat messages ([AcpChatTranscriptWriter]).
///
/// Personal stays `acp-transcript.jsonl`. Mixed seats use
/// `acp-transcript-<rosterMemberId>.jsonl`.
String acpTranscriptFileName({String? memberId, required bool personal}) {
  if (personal) return 'acp-transcript.jsonl';
  final id = memberId?.trim() ?? '';
  if (id.isEmpty) return 'acp-transcript.jsonl';
  return 'acp-transcript-$id.jsonl';
}

/// Agent-side session record ([AcpAgentSessionStore]) used to `session/load`.
///
/// Personal stays `acp-session.json`. Mixed seats use
/// `acp-session-<rosterMemberId>.json`.
String acpAgentSessionFileName({String? memberId, required bool personal}) {
  if (personal) return 'acp-session.json';
  final id = memberId?.trim() ?? '';
  if (id.isEmpty) return 'acp-session.json';
  return 'acp-session-$id.json';
}
