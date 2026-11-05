import 'package:ai_message_core/ai_message_core.dart';

import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../cli/registry/capabilities/ai_history_capability.dart';
import '../../cli/registry/cli_tool_registry.dart';
import '../../io/filesystem.dart';
import '../conversation/history/ai_history_locator.dart';
import '../conversation/history/session_history_context.dart';
import '../conversation/history/session_history_context_builder.dart';
import '../../storage/runtime_layout.dart';

import 'isolated_transcript_doc.dart';
import 'session_transcript_doc.dart';

export 'session_transcript_doc.dart';

/// A transcript search hit for one session seat.
class WorkspaceSessionContentMatch {
  const WorkspaceSessionContentMatch({
    required this.session,
    required this.memberId,
    this.memberLabel = '',
    required this.snippet,
    required this.messageIndex,
  });

  final AppSession session;

  /// '' for a simple (unteamed) seat; the roster member id for a team seat.
  final String memberId;

  /// Human-readable member label for team seats (the member **type**), empty
  /// for simple seats.
  final String memberLabel;

  /// A short window around the first match, collapsed to one line.
  final String snippet;

  /// Index into the seat's message list where the match starts.
  final int messageIndex;
}

class _Seat {
  const _Seat({
    required this.memberId,
    required this.cli,
    required this.memberLabel,
  });

  final String memberId;
  final CliTool cli;
  final String memberLabel;

  _Seat copyWith({CliTool? cli}) =>
      _Seat(memberId: memberId, cli: cli ?? this.cli, memberLabel: memberLabel);
}

class _SeatDoc {
  const _SeatDoc({
    required this.doc,
    required this.token,
    required this.warmedAt,
  });

  final SessionTranscriptDoc doc;
  final String token;
  final DateTime warmedAt;

  _SeatDoc copyWith({DateTime? warmedAt}) =>
      _SeatDoc(doc: doc, token: token, warmedAt: warmedAt ?? this.warmedAt);
}

/// Transcript text index for one workspace's sessions.
///
/// For each session seat (simple → one seat; team → one per roster member),
/// locates the on-disk transcript via [AiHistoryLocator], parses it with the
/// matching CLI's [AiTranscriptAdapter] (parse only — no enrich/inflate) and
/// projects it into a [SessionTranscriptDoc]; cold parses run on a background
/// isolate so warming a large session list does not stall frames. Docs are
/// cached keyed by `sessionId|memberId` and reused across keystrokes and dialog
/// opens, so [search] is a synchronous in-memory scan after the first [warm].
///
/// Seat freshness uses the transcript cache token (path+mtime+size) from the
/// locate hints plus a [WorkspaceSessionContentIndex.maxStale] TTL — cheap, no
/// filesystem watch. A seat that cannot be located/parsed is skipped (and its
/// stale doc dropped) rather than failing the whole search.
class WorkspaceSessionContentIndex {
  WorkspaceSessionContentIndex({
    required Filesystem fs,
    required RuntimeLayout layout,
    required String appDataRoot,
    CliToolRegistry? registry,
    this.cachedHistoryMessages,
  }) : _fs = fs,
       _layout = layout,
       _appDataRoot = appDataRoot,
       _registry = registry ?? CliToolRegistry.builtIn(),
       _locator = AiHistoryLocator(
         registry: registry ?? CliToolRegistry.builtIn(),
       );

  final Filesystem _fs;
  final RuntimeLayout _layout;
  final String _appDataRoot;
  final CliToolRegistry _registry;
  final AiHistoryLocator _locator;

  /// Chat-history messages for a seat when the transcript [token] still
  /// matches. Warm reuses this instead of a second [AiTranscriptAdapter.parse].
  final List<AiMessage>? Function({
    required String sessionId,
    required String memberId,
    required String token,
  })?
  cachedHistoryMessages;
  static final String _keySeparator = String.fromCharCode(0);

  static const _contextBuilder = SessionHistoryContextBuilder();

  /// Re-locate a seat's transcript once it is older than this. Generous so a
  /// stable workspace stays cached across dialog opens; small enough that a
  /// long-lived app eventually picks up messages written after the first warm.
  static const maxStale = Duration(minutes: 5);

  final Map<String, _SeatDoc> _docs = {};

  /// Background parse + projection worker; created on the first cold parse.
  IsolatedTranscriptDoc? _transcriptParser;

  /// Writes a transcript doc for every seat of [sessions] that is missing or
  /// stale. Cold parses run on a background worker ([IsolatedTranscriptDoc]) and
  /// the loop still yields between seats, so a large session list warms without
  /// blocking the UI. Per-seat errors are contained — one bad seat never aborts
  /// the warm.
  Future<void> warm({required List<AppSession> sessions}) async {
    var warmed = 0;
    for (final session in sessions) {
      for (final seat in _seatsFor(session)) {
        await _warmSeat(session, seat);
        if (++warmed % 4 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
  }

  /// Synchronously scans the cached transcript docs of [sessions] and returns
  /// at most one best match per session seat. Only seats already [warm]ed
  /// contribute; the dialog shows an indexing hint for the rest.
  List<WorkspaceSessionContentMatch> search(
    String query, {
    required List<AppSession> sessions,
  }) {
    final q = foldCasePreservingLength(query.trim());
    if (q.isEmpty) return const [];
    final out = <WorkspaceSessionContentMatch>[];
    for (final session in sessions) {
      for (final seat in _seatsFor(session)) {
        final doc = _docs[_seatKey(session.sessionId, seat.memberId)];
        if (doc == null) continue;
        final match = _matchInDoc(doc.doc, q, session: session, seat: seat);
        if (match != null) out.add(match);
      }
    }
    return out;
  }

  /// Drops cached docs for [sessionId] (e.g. when the user opens it and new
  /// messages may have arrived).
  void invalidateSession(String sessionId) {
    final prefix = '${sessionId.trim()}$_keySeparator';
    _docs.removeWhere((key, _) => key.startsWith(prefix));
  }

  void clear() => _docs.clear();

  /// Drops cached docs **and** releases the background parse worker. Called when
  /// the workspace goes away (tab closed / storage backend swapped).
  void dispose() {
    _transcriptParser?.dispose();
    _transcriptParser = null;
    _docs.clear();
  }

  Future<void> _warmSeat(AppSession session, _Seat seat) async {
    final key = _seatKey(session.sessionId, seat.memberId);
    final existing = _docs[key];
    if (existing != null &&
        DateTime.now().difference(existing.warmedAt) < maxStale) {
      return;
    }

    try {
      final located = await _locateTranscript(session, seat);
      if (located == null) {
        _docs.remove(key);
        return;
      }
      final token = located.bundle.hints['cacheToken'] ?? '';
      if (existing != null && existing.token == token) {
        // Unchanged since last warm — refresh the timestamp, skip the parse.
        _docs[key] = existing.copyWith(warmedAt: DateTime.now());
        return;
      }
      final cached = cachedHistoryMessages?.call(
        sessionId: session.sessionId,
        memberId: seat.memberId,
        token: token,
      );
      SessionTranscriptDoc doc;
      if (cached != null) {
        // The chat loader already parsed this seat: projecting it is cheap.
        doc = buildTranscriptDoc(cached);
      } else {
        final cap = _registry.capability<AiHistoryCapability>(located.cli);
        doc = cap == null
            ? buildTranscriptDoc(const <AiMessage>[])
            : await _parseOffIsolate(cap.adapter, located.bundle);
      }
      _docs[key] = _SeatDoc(doc: doc, token: token, warmedAt: DateTime.now());
    } on Object {
      _docs.remove(key);
    }
  }

  /// Parses + projects a transcript on the background worker, falling back to a
  /// local parse when the adapter (or its output) cannot cross the isolate
  /// boundary.
  Future<SessionTranscriptDoc> _parseOffIsolate(
    AiTranscriptAdapter adapter,
    AiTranscriptBundle bundle,
  ) async {
    final parser = _transcriptParser ??= IsolatedTranscriptDoc();
    try {
      return await parser.build(adapter, bundle);
    } on Object {
      if (identical(_transcriptParser, parser)) _transcriptParser = null;
      parser.dispose();
      return buildTranscriptDoc(await adapter.parse(bundle));
    }
  }

  /// Locates the seat's transcript with its resolved CLI, falling back to each
  /// remaining supported CLI (cheap stat probes) when the primary guess misses.
  Future<({AiTranscriptBundle bundle, CliTool cli})?> _locateTranscript(
    AppSession session,
    _Seat seat,
  ) async {
    final tools = <CliTool>[
      seat.cli,
      ...CliTool.values.where((t) => t != seat.cli),
    ];
    for (final tool in tools) {
      final ctx = _buildContext(session, seat.copyWith(cli: tool));
      final bundle = await _locator.locate(ctx: ctx, cli: tool);
      if (bundle != null) return (bundle: bundle, cli: tool);
    }
    return null;
  }

  SessionHistoryContext _buildContext(AppSession session, _Seat seat) {
    final isSimple = seat.memberId.isEmpty;
    return _contextBuilder.build(
      fs: _fs,
      layout: _layout,
      appDataRoot: _appDataRoot,
      session: session,
      memberId: seat.memberId,
      cli: seat.cli,
      teamId: isSimple ? null : session.sessionTeam,
    );
  }

  List<_Seat> _seatsFor(AppSession session) {
    if (session.sessionTeam.trim().isEmpty) {
      return [
        _Seat(
          memberId: '',
          cli: session.cli ?? CliTool.claude,
          memberLabel: '',
        ),
      ];
    }
    final teamCli = session.cli ?? CliTool.claude;
    return [
      for (final binding in session.members)
        _Seat(
          memberId: binding.rosterMemberId,
          cli: binding.cli ?? teamCli,
          memberLabel: binding.typeId.trim().isNotEmpty
              ? binding.typeId
              : binding.rosterMemberId,
        ),
    ];
  }

  static String _seatKey(String sessionId, String memberId) =>
      '${sessionId.trim()}$_keySeparator${memberId.trim()}';

  /// First case-insensitive occurrence of [query] in [text], returning the
  /// start index into [text].
  ///
  /// Length-safe: `String.toLowerCase()` can change a string's length (e.g.
  /// `ß` → `ss`), so an index found on a plain lowercased copy misaligns
  /// against the original. [foldCasePreservingLength] folds in place instead,
  /// keeping offsets valid for slicing.
  static int? caseInsensitiveIndexOf(String text, String query) {
    final q = query.trim();
    if (q.isEmpty) return null;
    final idx = foldCasePreservingLength(
      text,
    ).indexOf(foldCasePreservingLength(q.toLowerCase()));
    return idx < 0 ? null : idx;
  }

  static WorkspaceSessionContentMatch? _matchInDoc(
    SessionTranscriptDoc doc,
    String q, {
    required AppSession session,
    required _Seat seat,
  }) {
    // The doc keeps a pre-folded copy, so this is one plain string scan with no
    // per-keystroke regex compilation.
    final idx = doc.folded.indexOf(q);
    if (idx < 0) return null;
    return WorkspaceSessionContentMatch(
      session: session,
      memberId: seat.memberId,
      memberLabel: seat.memberLabel,
      snippet: snippetAround(doc.text, idx, q.length),
      messageIndex: messageIndexAt(doc.messageStarts, idx),
    );
  }

  static int messageIndexAt(List<int> starts, int offset) {
    var index = 0;
    for (var i = 0; i < starts.length; i++) {
      if (starts[i] > offset) break;
      index = i;
    }
    return index;
  }

  static String snippetAround(
    String text,
    int start,
    int queryLength, {
    int lead = 48,
    int trail = 96,
  }) {
    final s = start - lead < 0 ? 0 : start - lead;
    final e = start + queryLength + trail > text.length
        ? text.length
        : start + queryLength + trail;
    return text.substring(s, e).replaceAll('\n', ' ').trim();
  }
}
