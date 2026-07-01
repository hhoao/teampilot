import '../agent_node.dart';
import '../team_message.dart';

/// 协调策略读取的最小 roster 视图(由 TeamBus 提供)。
abstract interface class CoordinationView {
  AgentNode? member(String memberId);
  String? get teamLeadId;
}

/// **可插拔的团队协调拓扑**。把「谁该在何时收到通知」从总线核心抽出来:核心只管
/// 路由 + 状态机,拓扑(星型上报 / mesh / 层级…)由策略决定,新增拓扑不动核心。
///
/// 取代旧实现里硬编进 TeamBus 的 leader 星型上报 + 长在 [AgentNode] 上的
/// `hasUnreportedWork` 标志。
abstract interface class CoordinationPolicy {
  /// 有真实工作落入 [memberId] 的信箱(任意入站消息)。
  void noteInboundWork(String memberId);

  /// [memberId] 报告 idle。返回需要投递的协调消息(由总线按 eager 路由)。
  List<TeamMessage> onMemberIdle(CoordinationView view, String memberId);

  /// worker 经 [TeamBus.receiveWork] 已向 leader 上报 idle 后调用，避免
  /// [onMemberIdle] 协调路径重复投递。
  void markIdleReported(String memberId);
}
