import '../../../utils/logger.dart';
import 'bus_observation.dart';

/// 领域事件的去处。默认 [LoggingBusEventSink];测试可注入捕获型 sink 做断言。
abstract interface class BusEventSink {
  void emit(BusObservation observation);
}

/// 丢弃所有事件。
class NoopBusEventSink implements BusEventSink {
  const NoopBusEventSink();
  @override
  void emit(BusObservation observation) {}
}

/// 把事件落到 [appLogger]。丢弃/回滚是 warn,其余 debug。
class LoggingBusEventSink implements BusEventSink {
  const LoggingBusEventSink();

  @override
  void emit(BusObservation o) {
    switch (o) {
      case MessageRouted(:final messageId, :final to, :final from):
        appLogger.d('[team-bus] routed $messageId $from→$to');
      case MessageDropped(:final messageId, :final reason, :final to):
        appLogger.w('[team-bus] dropped $messageId (reason=$reason, to=$to)');
      case MemberDoorbelled(:final memberId):
        appLogger.d('[team-bus] doorbell → $memberId');
      case BatchTaken(:final memberId, :final count):
        appLogger.d('[team-bus] $memberId took $count');
      case DeliveryConfirmed(:final memberId, :final count):
        appLogger.d('[team-bus] $memberId confirmed $count read');
      case DeliveryRolledBack(:final memberId, :final count):
        appLogger.w('[team-bus] $memberId rolled back $count (client gone)');
    }
  }
}
