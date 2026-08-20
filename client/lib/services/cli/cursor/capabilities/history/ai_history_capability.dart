import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:path/path.dart' as p;

import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import '../../provider/cursor_windows_home_junction.dart';
import '../tool_call_resolvers.dart';
import 'ai_transcript.dart';
import 'side_resolver.dart';
import 'terminal_tool_result_enricher.dart';

final class CursorAiHistoryCapability implements AiHistoryCapability {
  const CursorAiHistoryCapability({
    this.shellResolver = CursorToolCallResolvers.shellResolverInstance,
    this.subagentSideResolver = const CursorSideResolver(),
  });

  @override
  final AiShellToolTargetResolver shellResolver;

  static const _resolvers = CursorToolCallResolvers();

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateCursorTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const CursorAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend get lineAppend => appendCursorJsonlEvent;

  @override
  String get tailFallbackPrefix => 'cursor';

  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  ToolResultEnricher get toolResultEnricher => CursorTerminalToolResultEnricher(
        shellResolver: shellResolver,
      );

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptIncrementalRefresher? get incrementalRefresher => null;

  /// Cursor isolates a fake `$HOME` whose parent of the session CONFIG_DIR
  /// (`<toolDir>/home`) is the session's history home.
  @override
  Map<String, String> sessionEnv({String? toolRoot}) {
    final env = <String, String>{};
    if (toolRoot != null && toolRoot.isNotEmpty) {
      env['CURSOR_CONFIG_DIR'] = toolRoot;
      final home = p.dirname(toolRoot);
      env['HOME'] = home;
      env['USERPROFILE'] = home;
    }
    return env;
  }

  /// `postCaptured`: cursor stores each chat under the isolated fake `$HOME`
  /// (`<toolDir>/home/.cursor/chats/<workspaceHash>/<chatId>/`). Standalone
  /// and mixed members both isolate HOME per TeamPilot session, so a fresh
  /// launch finds an empty chats dir (cursor mints a new chat) and reopen
  /// scans that session's store for `--resume`.
  ///
  /// We do **not** pre-allocate via `cursor-agent create-chat`: that makes an
  /// empty chat (`"hasConversation": false`) which diverges from the chat the
  /// interactive session actually writes to, so resume would restore nothing.
  @override
  ResumeBinding get binding => ResumeBinding.postCaptured;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (persisted.isNotEmpty) return persisted;

    final configDir = await CursorWindowsHomeJunction.resolveCursorConfigDir(
      fs: ctx.fs,
      env: ctx.env,
    );
    if (configDir == null) return null;
    final path = ctx.fs.pathContext;
    final chatsRoot = path.join(configDir, 'chats');

    String? best;
    var bestUpdated = -1;
    try {
      for (final wsHash in await ctx.fs.listDir(chatsRoot)) {
        if (!wsHash.isDirectory) continue;
        final wsDir = path.join(chatsRoot, wsHash.name);
        for (final chat in await ctx.fs.listDir(wsDir)) {
          if (!chat.isDirectory) continue;
          final metaRaw = await ctx.fs.readString(
            path.join(wsDir, chat.name, 'meta.json'),
          );
          if (metaRaw == null || metaRaw.isEmpty) continue;
          final meta = _decode(metaRaw);
          if (meta == null || meta['hasConversation'] != true) continue;
          final updated = (meta['updatedAtMs'] as num?)?.toInt() ?? 0;
          if (updated > bestUpdated) {
            bestUpdated = updated;
            best = chat.name;
          }
        }
      }
    } on Object {
      return null;
    }
    return best;
  }

  static Map<String, Object?>? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    }
  }

  @override
  AiEditToolTargetResolver get editResolver => _resolvers.editResolver;

  @override
  AiToolFileTargetResolver get fileResolver => _resolvers.fileResolver;

  @override
  AiToolCallCategoryResolver get categoryResolver =>
      _resolvers.categoryResolver;
}
