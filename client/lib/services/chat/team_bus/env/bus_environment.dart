import 'package:uuid/uuid.dart';

import 'bus_event_sink.dart';

/// 总线的环境注入点:时钟 + id 生成 + 事件去处。一处注入、贯穿
/// TeamBus / MemberInbox / CoordinationPolicy / MCP handler,消除散落的
/// `DateTime.now()` / `Uuid()` 直连,测试可确定性化。
class BusEnvironment {
  BusEnvironment({
    int Function()? clock,
    String Function()? ids,
    BusEventSink? events,
  }) : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       ids = ids ?? (() => const Uuid().v4()),
       events = events ?? const LoggingBusEventSink();

  /// 毫秒时间戳(日志 createdAt / read-event at / idle 时间戳)。
  final int Function() clock;

  /// 消息 id(路由去重 / 排序)。
  final String Function() ids;

  /// 结构化领域事件去处。
  final BusEventSink events;
}
