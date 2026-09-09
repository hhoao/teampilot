import 'dart:async';

import 'package:meta/meta.dart';

import '../../utils/logging/logger.dart';

/// 定时自动 fetch 的调度器：只负责计时与并发合并，fetch 本体由构造注入
/// （生产环境接 `GitHistoryActions.fetchAllQuiet`）。失败静默记日志——
/// 后台刷新不是用户操作，不打扰 UI；挂死的 fetch 由 [timeout] 兜底放弃。
class GitAutoFetchScheduler {
  GitAutoFetchScheduler({
    required Future<void> Function(String dir) fetch,
    required void Function() onFetched,
    required Duration interval,
    this.timeout = const Duration(seconds: 60),
  }) : _fetch = fetch,
       _onFetched = onFetched,
       _interval = interval;

  final Future<void> Function(String dir) _fetch;
  final void Function() _onFetched;
  final Duration _interval;
  final Duration timeout;

  Timer? _timer;
  String? _targetRoot;
  bool _fetchInFlight = false;

  bool get isRunning => _timer != null;
  String? get targetRoot => _targetRoot;

  /// 启动或重定向目标。已在该 root 上运行时是 no-op（不重置计时）；
  /// 否则重置计时并立即 fetch 一次——面板恢复可见/切换仓库时即刻同步。
  void start(String root) {
    if (isRunning && _targetRoot == root) return;
    _timer?.cancel();
    _targetRoot = root;
    _timer = Timer.periodic(_interval, (_) => tick());
    _fetchNow();
  }

  /// 暂停：取消计时但保留目标 root（恢复 = 对同一 root 再 [start]）。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _targetRoot = null;
  }

  @visibleForTesting
  void tick() => _fetchNow();

  Future<void> _fetchNow() async {
    final root = _targetRoot;
    if (root == null || _fetchInFlight) return;
    _fetchInFlight = true;
    try {
      await _fetch(root).timeout(timeout);
      _onFetched();
    } on Exception catch (e) {
      appLogger.w('[GitAutoFetch] fetch failed for $root: $e');
    } finally {
      _fetchInFlight = false;
    }
  }
}
