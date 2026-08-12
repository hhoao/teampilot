import 'package:flutter/foundation.dart';

import '../logging/logger_utils.dart';

/// `buildWhen` 包装器：按 [changed] 中"字段名 → 是否变化"判断是否重建，
/// 并在 debug 模式下打印本次具体是哪些字段的变化触发了 rebuild。
///
/// 用法：
/// ```dart
/// buildWhen: (p, c) => debugBuildWhen(p, c,
///   tag: 'my_widget',
///   changed: {
///     'status': p.status != c.status,
///     'sessionId': p.sessionId != c.sessionId,
///   },
/// ),
/// ```
bool debugBuildWhen<T>(
  T previous,
  T current, {
  String? tag,
  required Map<String, bool> changed,
  bool enable = true,
}) {
  final needsRebuild = changed.containsValue(true);
  if (kDebugMode && needsRebuild && enable) {
    final fields = changed.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    AppLogger.instance.d(
      '[rebuild]${tag == null ? '' : '[$tag]'} changed: $fields',
    );
  }
  return needsRebuild;
}
