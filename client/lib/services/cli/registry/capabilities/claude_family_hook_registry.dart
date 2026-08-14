/// 装配点工具：把 [hooksSection]（统一 writer 输出的 `settings.json` 片段）
/// 幂等并入 settings 的 `hooks` 段（按 (event, url|command) 判重，重复不追加）。
/// Task 19 收敛后为唯一装配入口（旧 CliHookSpec 资产注册路径已删除）。
Map<String, Object?> mergeHooksInto(
  Map<String, Object?> settings,
  Map<String, Object?> hooksSection,
) {
  final merged = Map<String, Object?>.from(settings);
  final hooks = Map<String, Object?>.from(
    (merged['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
  );
  for (final entry in (hooksSection['hooks'] as Map).entries) {
    final event = entry.key as String;
    final incoming = List<Object?>.from((entry.value as List?) ?? const []);
    final existing = List<Object?>.from((hooks[event] as List?) ?? const []);
    for (final inc in incoming) {
      if (!existing.any((e) => _sameHookEntry(e, inc))) existing.add(inc);
    }
    hooks[event] = existing;
  }
  // 空合并且原 settings 无 hooks 键 → 保持"无 hooks 键"的缺席语义（占位资产
  // 未补全时不会写入 hooks: {}）。
  if (hooks.isEmpty && !merged.containsKey('hooks')) return merged;
  merged['hooks'] = hooks;
  return merged;
}

bool _sameHookEntry(Object? a, Object? b) {
  if (a is! Map || b is! Map) return false;
  final ha = a['hooks'];
  final hb = b['hooks'];
  if (ha is! List || hb is! List || ha.isEmpty || hb.isEmpty) return false;
  final fa = ha.first as Map;
  final fb = hb.first as Map;
  return (fa['url'] ?? fa['command']) == (fb['url'] ?? fb['command']);
}
