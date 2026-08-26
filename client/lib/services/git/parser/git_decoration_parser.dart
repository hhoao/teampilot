import '../../../models/git_graph.dart';

/// 把 `%d` 输出（形如 `(HEAD -> main, origin/main, tag: v1.0)`）解析为装饰列表。
///
/// 远端分支判定优先用 [remotePrefixes]（来自 `git remote` 加 `/` 后缀）；
/// 缺省时退回 `origin/` 启发式。
List<GitRefDecoration> parseGitDecorations(
  String raw, {
  Set<String> remotePrefixes = const {'origin/'},
}) {
  final body = raw.trim();
  if (!body.startsWith('(') || !body.endsWith(')')) return const [];
  final inner = body.substring(1, body.length - 1).trim();
  if (inner.isEmpty) return const [];
  final out = <GitRefDecoration>[];
  for (final part in inner.split(',')) {
    final token = part.trim();
    if (token.isEmpty) continue;
    if (token == 'HEAD') {
      out.add(const GitRefDecoration(GitRefDecorationKind.head, ''));
    } else if (token.startsWith('HEAD -> ')) {
      out.add(GitRefDecoration(
        GitRefDecorationKind.head,
        token.substring('HEAD -> '.length).trim(),
      ));
    } else if (token.startsWith('tag: ')) {
      out.add(GitRefDecoration(
        GitRefDecorationKind.tag,
        token.substring('tag: '.length).trim(),
      ));
    } else if (remotePrefixes.any((p) => token.startsWith(p))) {
      out.add(GitRefDecoration(GitRefDecorationKind.remoteBranch, token));
    } else {
      out.add(GitRefDecoration(GitRefDecorationKind.localBranch, token));
    }
  }
  return out;
}
