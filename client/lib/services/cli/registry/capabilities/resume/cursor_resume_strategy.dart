import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../../../provider/cursor/cursor_home_layout.dart';
import '../session_resume_capability.dart';

/// `postCaptured` strategy for cursor. cursor stores each chat under the
/// per-session-isolated config root's `chats/<workspaceHash>/<chatId>/`
/// (with a `meta.json`), so — like codex/opencode — we let cursor mint its own
/// chat on the fresh launch and, on reopen, capture the real chat to `--resume`.
///
/// Standalone launches set `$CURSOR_CONFIG_DIR` to the isolated `.cursor` dir;
/// mixed-mode members only isolate via fake `$HOME`, so chats live under
/// `$HOME/.cursor/chats/` instead.
///
/// We do **not** pre-allocate via `cursor-agent create-chat`: that makes an
/// empty chat (`"hasConversation": false`) which diverges from the chat the
/// interactive session actually writes to, so resume would restore nothing.
final class CursorResumeStrategy implements SessionResumeCapability {
  const CursorResumeStrategy();

  @override
  ResumeBinding get binding => ResumeBinding.postCaptured;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    final configDir = _cursorConfigRoot(ctx.env, ctx.fs.pathContext);
    if (configDir == null) return null;
    final path = ctx.fs.pathContext;
    final chatsRoot = path.join(configDir, 'chats');

    // Always scan (cheap, per-session isolated) so a stale/empty persisted id
    // never shadows the real conversation: pick the chat with a real
    // conversation and the newest update.
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

  static String? _cursorConfigRoot(Map<String, String> env, p.Context path) {
    final explicit = env['CURSOR_CONFIG_DIR']?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final home = env['HOME']?.trim() ?? '';
    if (home.isEmpty) return null;
    return path.join(home, CursorHomeLayout.cursorDirName);
  }

  static Map<String, Object?>? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    }
  }
}
