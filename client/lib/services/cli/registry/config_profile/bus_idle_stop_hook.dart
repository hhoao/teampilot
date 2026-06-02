/// mixed 模式：往成员 settings 的 `hooks.Stop` 加一个 http hook —— turn 结束时
/// POST `/idle`（带 `X-Member`）。server 在响应里回 `decision:block`，把成员拦在
/// 停止前、推回 `wait_for_message`（claude/flashskyai 同一套 Stop-hook 协议）。
Map<String, Object?> mergeStopIdleHook(
  Map<String, Object?> settings,
  String memberId,
  String idleUrl,
) {
  final hooks = Map<String, Object?>.from(
    (settings['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
  );
  final stop = List<Object?>.from((hooks['Stop'] as List?) ?? const []);
  final exists = stop.any(
    (e) =>
        e is Map &&
        (e['hooks'] as List?)?.any(
              (h) => h is Map && h['url'] == idleUrl,
            ) ==
            true,
  );
  if (!exists) {
    stop.add({
      'hooks': [
        {
          'type': 'http',
          'url': idleUrl,
          'headers': {'X-Member': memberId},
        },
      ],
    });
  }
  hooks['Stop'] = stop;
  return {...settings, 'hooks': hooks};
}
