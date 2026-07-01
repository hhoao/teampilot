import '../../../team_bus/member_bus_idle_endpoint.dart';

/// mixed 模式：往成员 settings 的 `hooks.Stop` 加一个 http hook —— turn 结束时
/// POST `/idle`（带 `X-Member`，远程再加 `X-Bus-Token`）。server 只回
/// `decision:block`（或放行 `{}`），把成员拦在停止前、推回 `wait_for_message`；
/// 不触发 bus [TeamBus.onMemberIdle]。
Map<String, Object?> mergeStopIdleHook(
  Map<String, Object?> settings,
  String memberId,
  MemberBusIdleEndpoint idle,
) {
  final hooks = Map<String, Object?>.from(
    (settings['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
  );
  final stop = List<Object?>.from((hooks['Stop'] as List?) ?? const []);
  final exists = stop.any(
    (e) =>
        e is Map &&
        (e['hooks'] as List?)?.any(
              (h) => h is Map && h['url'] == idle.url,
            ) ==
            true,
  );
  if (!exists) {
    stop.add({
      'hooks': [
        {
          'type': 'http',
          'url': idle.url,
          'headers': idle.headersFor(memberId),
        },
      ],
    });
  }
  hooks['Stop'] = stop;
  return {...settings, 'hooks': hooks};
}
