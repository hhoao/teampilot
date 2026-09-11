import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../models/layout_preferences.dart';
import 'git_graph_columns.dart';

/// 一次解析后的列布局：图区宽 + 各元数据列宽（隐藏列为 0 且不参与行内排布）。
@immutable
class GitGraphColumnLayout {
  const GitGraphColumnLayout({
    required this.prefs,
    required this.graphWidth,
  });

  final GitGraphColumnPrefs prefs;

  /// 统一图区宽度（按已加载行的最大 slot 计算；行 / 列头 / 伪行共用）。
  final double graphWidth;

  bool isHidden(GitGraphColumnId id) => prefs.hiddenColumns.contains(id);

  double widthOf(GitGraphColumnId id) =>
      isHidden(id) ? 0 : prefs.widthOf(id);

  static GitGraphColumnLayout resolve({
    required GitGraphColumnPrefs prefs,
    required int maxSlot,
  }) => GitGraphColumnLayout(
    prefs: prefs,
    graphWidth: GitGraphColumns.graphWidthFor(maxSlot: maxSlot),
  );
}

/// 列头拖拽与偏好同步的控制器。
///
/// 拖拽过程中本地 [notifyListeners] 驱动行 / 列头实时跟随；
/// [commit] 才写入 [LayoutCubit]（与 IDE 分栏「拖完才存」一致，避免拖动
/// 期间每像素落盘）。外部偏好变化（工具栏菜单隐藏列）经 [sync] 回灌。
class GitGraphColumnLayoutController extends ChangeNotifier {
  GitGraphColumnLayoutController({required this.maxSlot})
    : _prefs = const GitGraphColumnPrefs();

  GitGraphColumnPrefs _prefs;

  /// 当前已加载行的最大 slot；行数据翻页后由宿主更新。
  int maxSlot;

  GitGraphColumnLayout get layout => GitGraphColumnLayout.resolve(
    prefs: _prefs,
    maxSlot: maxSlot,
  );

  /// 偏好变化（含首次挂载）时同步；maxSlot 变化也在此更新（不单独 notify
  /// 的调用方需要手动 [notify] 时除外——本方法总是通知）。
  void sync(GitGraphColumnPrefs prefs, {int? newMaxSlot}) {
    if (newMaxSlot != null) maxSlot = newMaxSlot;
    if (prefs == _prefs && newMaxSlot == null) return;
    _prefs = prefs;
    notifyListeners();
  }

  /// 拖拽更新某列宽（clamp 由 [GitGraphColumnPrefs.copyWith] 保证）。
  void resizeDrag(GitGraphColumnId id, double width) {
    final next = _prefs.withWidth(id, width);
    if (next == _prefs) return;
    _prefs = next;
    notifyListeners();
  }

  // --- 列头分隔条拖拽 ---

  GitGraphColumnId? _dragColumn;
  bool _dragInvert = false;
  double _dragStartDx = 0;
  double _dragStartWidth = 0;

  /// 拖拽中的列（分隔条加粗反馈）。
  GitGraphColumnId? get resizingColumn => _dragColumn;

  /// 拖拽开始。[column] 为本次调整的列——分隔条**左侧**的固定列；
  /// 首条分隔条左侧是弹性的描述列，改为调整右侧列并取 [invert]（拖右
  /// =收窄该列），使分隔条始终跟随光标方向移动。
  void beginResize({
    required GitGraphColumnId column,
    required bool invert,
    required double globalDx,
  }) {
    _dragColumn = column;
    _dragInvert = invert;
    _dragStartDx = globalDx;
    _dragStartWidth = _prefs.widthOf(column);
    notifyListeners();
  }

  /// 拖拽移动：按指针位移更新目标列宽（clamp 由 copyWith 保证）。
  void updateResize(double globalDx) {
    final column = _dragColumn;
    if (column == null) return;
    var delta = globalDx - _dragStartDx;
    if (_dragInvert) delta = -delta;
    resizeDrag(column, _dragStartWidth + delta);
  }

  /// 拖拽结束：清除反馈并把当前偏好持久化到 [LayoutCubit]。
  void commit(BuildContext context) {
    if (_dragColumn == null) return;
    _dragColumn = null;
    notifyListeners();
    context.read<LayoutCubit>().setGitGraphColumns(_prefs);
  }
}
