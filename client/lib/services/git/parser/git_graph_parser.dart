import 'dart:convert';

import '../../../models/git_graph.dart';
import 'git_decoration_parser.dart';

/// `git log --graph --pretty=format:%x1e%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%d%x1f%s`
/// 输出的逐行解析器。
///
/// git 的 graph 每个 lane 占 2 个字符：偶数位是 lane 中心（`|`/`*`，lane =
/// index ~/ 2），奇数位是 lane 间空隙（`\`/`/` 曲线，或折叠过程中的中转位）。
/// 本解析器以 **slot**（字符列号）为几何坐标：偶数 slot = lane 中心，奇数
/// slot = 半 lane 偏移的空隙位。拓扑正确性由 git 保证，这里只做"字符 → 几何"映射：
///
/// - `|`@slot：竖线（含罕见的奇数位竖线，按空隙位 x 渲染）。
/// - `\`@slot：分叉曲线，从左侧 lane 中心弯向右侧新 lane 中心（ASCII 扇形级联）。
/// - `/`@slot：常规左移，从右侧 lane 中心到左侧 lane 中心；跨 lane 穿越时经过
///   空隙位中转（见 [_LayoutState] 的在途线追踪）。
/// - ` / `（两侧皆空的孤 `/`）：两条 lane 线交换位置（git replace 改写父子关系
///   时出现），输出一对交叉边，保证两端节点都有连线。
class GitGraphParser {
  static const String recordSep = '\x1e';
  static const String fieldSep = '\x1f';

  static List<GitGraphRow> parse(
    String stdout, {
    Set<String> remotePrefixes = const {'origin/'},
  }) {
    final state = _LayoutState();
    final rows = <GitGraphRow>[];
    final lines = const LineSplitter().convert(stdout);
    for (var n = 0; n < lines.length; n++) {
      final line = lines[n];
      final sepIndex = line.indexOf(recordSep);
      final graphPart =
          line.substring(0, sepIndex < 0 ? line.length : sepIndex);
      final nextPart = _graphPartOf(lines, n + 1);
      final edges = _parseGeometry(graphPart, nextPart, state);
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
        node: GitGraphNode(state.nodeSlot ?? 0, state.nodeColor),
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

  static String _graphPartOf(List<String> lines, int n) {
    if (n >= lines.length) return '';
    final line = lines[n];
    final sepIndex = line.indexOf(recordSep);
    return line.substring(0, sepIndex < 0 ? line.length : sepIndex);
  }

  static bool _hasChar(String g, int slot, String ch) =>
      slot >= 0 && slot < g.length && g[slot] == ch;

  static bool _isLineChar(String g, int slot) =>
      _hasChar(g, slot, '|') || _hasChar(g, slot, '*');

  /// 扫描一行的 ASCII 前缀，产出边列表；节点 slot 记录在 [state]。
  static List<GitGraphEdge> _parseGeometry(
    String g,
    String next,
    _LayoutState state,
  ) {
    state.beginRow();
    state.nodeSlot = null;
    state.nodeColor = 0;
    final out = <GitGraphEdge>[];
    void addEdge(int from, int to, int color) {
      if (out.any((e) => e.fromSlot == from && e.toSlot == to)) return;
      out.add(GitGraphEdge(from, to, color));
    }

    for (var i = 0; i < g.length; i++) {
      switch (g[i]) {
        case '*':
          {
            state.nodeSlot = i;
            state.nodeColor = state.colorFor(i ~/ 2);
            addEdge(i, i, state.nodeColor);
            break;
          }
        case '|':
          {
            final color = state.transitAt(i) ?? state.colorFor(i ~/ 2);
            addEdge(i, i, color);
            break;
          }
        case '\\':
          {
            // 分叉曲线取新分支（下方新出现的 lane）的颜色。
            addEdge(i - 1, i + 1, state.colorFor(i ~/ 2 + 1));
            break;
          }
        case '/':
          {
            _parseSlash(g, next, i, state, addEdge);
            break;
          }
        default:
          break; // 空格、'-'、'_' 等填充符
      }
    }
    return out;
  }

  /// `/`@i：i 为奇数（lane i~/2 与 lane i~/2+1 之间的空隙）。
  static void _parseSlash(
    String g,
    String next,
    int i,
    _LayoutState state,
    void Function(int, int, int) addEdge,
  ) {
    final left = i - 1; // 左侧 lane 中心 slot（偶数）
    final right = i + 1; // 右侧 lane 中心 slot（偶数）
    final leftLane = i ~/ 2;
    final rightLane = leftLane + 1;

    // 两侧 lane 中心在本行都无线（无 `|`/`*`），且下一行右侧 slot 有线：
    // 两条 lane 线交换位置（左右各一条，同时移动），ASCII 只画一个 '/'。
    if (!_isLineChar(g, left) && !_isLineChar(g, right) &&
        _isLineChar(next, right)) {
      final leftColor = state.colorFor(leftLane);
      final rightColor = state.colorFor(rightLane);
      addEdge(left, right, leftColor);
      addEdge(right, left, rightColor);
      state.swapColors(leftLane, rightLane);
      return;
    }

    // 常规左移。若上一行的 `/` 已把线挪进空隙（在途线），从空隙续接，
    // 并沿用该线的颜色——穿越其它 lane 时不能改成被穿越 lane 的颜色。
    final transitColor = state.takeTransit(i + 2);
    final fromSlot = transitColor != null ? i + 2 : right;
    final color = transitColor ?? state.colorFor(rightLane);
    // 下一行继续左移（或竖在空隙位）→ 本行止于空隙；否则落到左侧 lane 中心。
    final continues =
        _hasChar(next, i - 2, '/') || _hasChar(next, i, '|');
    final toSlot = continues ? i : left;
    if (continues) state.setTransit(i, color);
    addEdge(fromSlot, toSlot, color);
  }
}

/// 跨行的布局状态：lane 首次触达时取下一个调色板序号；在途线（已进入 lane
/// 间空隙、仍在横穿的线）按空隙 slot 追踪，保证颜色随线走。
class _LayoutState {
  final Map<int, int> _colors = {};
  int _nextColor = 0;
  int? nodeSlot;
  int nodeColor = 0;

  Map<int, int> _transitNow = {};
  Map<int, int> _transitNext = {};

  /// 每行开始：上一行登记的在途线生效，未被续接的（已落定/汇入节点）作废。
  void beginRow() {
    _transitNow = _transitNext;
    _transitNext = {};
  }

  int colorFor(int lane) => _colors.putIfAbsent(lane, () => _nextColor++);

  void swapColors(int a, int b) {
    final ca = colorFor(a);
    final cb = colorFor(b);
    _colors[a] = cb;
    _colors[b] = ca;
  }

  int? transitAt(int slot) => _transitNow[slot];

  int? takeTransit(int slot) => _transitNow.remove(slot);

  void setTransit(int slot, int color) => _transitNext[slot] = color;
}
