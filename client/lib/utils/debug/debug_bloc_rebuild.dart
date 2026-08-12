import 'package:flutter/foundation.dart';

import '../logging/logger_utils.dart';

/// `buildWhen` 包装器：按 [fields] 给出的"字段名 → 值"自动 diff，判断是否重建，
/// 并在 debug 模式下打印本次具体是哪些字段的变化触发了 rebuild。
///
/// 用法：
/// ```dart
/// buildWhen: (p, c) => debugBuildWhen(p, c,
///   tag: 'my_widget',
///   fields: (s) => s.rebuildDebugFields,
/// ),
/// ```
bool debugBuildWhen<T>(
  T previous,
  T current, {
  String? tag,
  required Map<String, Object?> Function(T state) fields,
}) {
  final prev = fields(previous);
  final curr = fields(current);
  final changed = <String>[
    for (final key in {...prev.keys, ...curr.keys})
      if (prev[key] != curr[key]) key,
  ];
  if (kDebugMode && changed.isNotEmpty) {
    AppLogger.instance.d(
      '[rebuild]${tag == null ? '' : '[$tag]'} changed: $changed',
    );
  }
  return changed.isNotEmpty;
}
