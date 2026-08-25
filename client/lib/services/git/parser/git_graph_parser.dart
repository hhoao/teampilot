import 'dart:convert';

import '../../../models/git_graph.dart';
import 'git_decoration_parser.dart';

/// `git log --graph --pretty=format:%x1e%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%d%x1f%s`
/// 输出的逐行解析器。
///
/// git 的 graph 列每 lane 占 2 个字符：`|`/`*` 在偶数位（lane = index ~/ 2），
/// `\`/`/` 曲线在奇数位。拓扑正确性由 git 保证，这里只做"字符 → 几何"映射。
class GitGraphParser {
  static const String recordSep = '\x1e';
  static const String fieldSep = '\x1f';

  static List<GitGraphRow> parse(
    String stdout, {
    Set<String> remotePrefixes = const {'origin/'},
  }) {
    final state = _LayoutState();
    final rows = <GitGraphRow>[];
    for (final line in const LineSplitter().convert(stdout)) {
      final sepIndex = line.indexOf(recordSep);
      final graphPart =
          line.substring(0, sepIndex < 0 ? line.length : sepIndex);
      final edges = _parseGeometry(graphPart, state);
      if (sepIndex < 0) {
        if (graphPart.trim().isEmpty) continue;
        rows.add(GitGraphSpacerRow(edges: edges));
        continue;
      }
      final fields = line.substring(sepIndex + recordSep.length).split(fieldSep);
      if (fields.length < 7) continue;
      final ts = int.tryParse(fields[4]);
      if (ts == null) continue;
      rows.add(GitCommitRow(
        edges: edges,
        node: GitGraphNode(state.nodeLane ?? 0, state.nodeColor),
        hash: fields[0],
        parents: fields[1].trim().isEmpty
            ? const []
            : fields[1].trim().split(' '),
        authorName: fields[2],
        authorEmail: fields[3],
        authorDate:
            DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
        subject: fields[6],
        refs: parseGitDecorations(fields[5], remotePrefixes: remotePrefixes),
      ));
    }
    return rows;
  }

  /// 扫描一行的 ASCII 前缀，产出边列表；节点 lane 记录在 [state]。
  static List<GitGraphEdge> _parseGeometry(String g, _LayoutState state) {
    state.nodeLane = null;
    state.nodeColor = 0;
    final out = <GitGraphEdge>[];
    void addEdge(int from, int to, int color) {
      if (out.any((e) => e.fromLane == from && e.toLane == to)) return;
      out.add(GitGraphEdge(from, to, color));
    }

    for (var i = 0; i < g.length; i++) {
      switch (g[i]) {
        case '*':
          {
            final lane = i ~/ 2;
            state.nodeLane = lane;
            state.nodeColor = state.colorFor(lane);
            addEdge(lane, lane, state.nodeColor);
            break;
          }
        case '|':
          {
            final lane = i ~/ 2;
            addEdge(lane, lane, state.colorFor(lane));
            break;
          }
        case '\\':
          {
            final lane = i ~/ 2;
            // 分叉曲线取新分支（下方新出现的 lane）的颜色。
            addEdge(lane, lane + 1, state.colorFor(lane + 1));
            break;
          }
        case '/':
          {
            final lane = i ~/ 2;
            // 合流曲线保留侧支 lane 的颜色直到汇入。
            addEdge(lane + 1, lane, state.colorFor(lane + 1));
            break;
          }
        default:
          break; // 空格、'-'、'_' 等填充符
      }
    }
    return out;
  }
}

/// 跨行的调色板分配状态：lane 首次触达时取下一个颜色序号。
class _LayoutState {
  final Map<int, int> _colors = {};
  int _nextColor = 0;
  int? nodeLane;
  int nodeColor = 0;

  int colorFor(int lane) => _colors.putIfAbsent(lane, () => _nextColor++);
}
