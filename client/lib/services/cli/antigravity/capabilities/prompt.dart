import 'package:path/path.dart' as p;

import '../../registry/capabilities/prompt_capability.dart';

/// Antigravity (Gemini-family) reads project rules from
/// `<config>/rules/*.md` under its fake HOME, so the assembled prompt is
/// materialized there instead of a `GEMINI.md` memory file.
abstract final class AntigravityPromptPaths {
  static String rulesPath(String sessionToolDir) => p.join(
    sessionToolDir,
    'home',
    '.gemini',
    'config',
    'rules',
    'teampilot.md',
  );
}

final class AntigravityPromptCapability implements PromptCapability {
  const AntigravityPromptCapability();

  @override
  Future<PromptMaterializeResult> materialize(
    PromptMaterializeContext ctx, {
    required PromptDocument document,
  }) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    if (paths == null || scope == null || document.content.isEmpty) {
      return const PromptMaterializeResult();
    }
    final toolDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      'antigravity',
      memberId: scope.memberId,
    );
    final path = AntigravityPromptPaths.rulesPath(toolDir);
    await paths.fs.ensureDir(paths.fs.pathContext.dirname(path));
    await paths.fs.atomicWrite(path, '${document.content}\n');
    return const PromptMaterializeResult(written: true);
  }
}
