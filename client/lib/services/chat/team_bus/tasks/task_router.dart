import 'team_task.dart';

/// 任务路由的**纯函数**核心：合格性、打分、阶段迁移。无 IO、无自有时钟（时间由调用
/// 方传入）。push（[TaskQueue.claimNext]）、pull（[TaskQueue.claimSpecific]）、reconcile
/// 三条路径共用同一套判定，保证语义一致。
class TaskRouter {
  const TaskRouter._();

  /// 任务在**当前阶段**实际要求的能力集合。matched 用硬性 required；widened 放宽到
  /// preferred；open 无要求；reserved 同 matched（再叠加点名门控，见 [eligible]）。
  static Set<String> effectiveRequiredCaps(TeamTask t) {
    switch (t.routing.stage) {
      case RoutingStage.reserved:
      case RoutingStage.matched:
        return t.requiredCapabilities;
      case RoutingStage.widened:
        return t.preferredCapabilities;
      case RoutingStage.open:
        return const {};
    }
  }

  /// 成员对任务是否合格：reserved 阶段仅点名者；其余阶段按 `caps ⊇ 当前要求` 判定。
  static bool eligible(String memberId, Set<String> memberCaps, TeamTask t) {
    if (t.routing.stage == RoutingStage.reserved) {
      final assignee = t.preferredAssignee;
      if (assignee != null && assignee != memberId) return false;
    }
    final required = effectiveRequiredCaps(t);
    for (final cap in required) {
      if (!memberCaps.contains(cap)) return false;
    }
    return true;
  }

  /// 适配度打分：与 preferredCapabilities 的交集大小。越大越合适。
  static int score(Set<String> memberCaps, TeamTask t) {
    var n = 0;
    for (final cap in t.preferredCapabilities) {
      if (memberCaps.contains(cap)) n++;
    }
    return n;
  }

  /// 给定当前时间与「是否存在合格的在线 / 可拉起成员」，算出下一阶段（单调，不回退）。
  ///
  /// **死锁加速（A'）**：当**没有任何合格成员**（[hasEligibleLiveMember] 与
  /// [hasEligibleEngageableMember] 皆空）时跳过时间窗**立即降级**——「先拉人、
  /// 后放宽」的拉人步骤已不可能成功（在线没人能领、declared 也没人能拉起），
  /// 再等窗口只是白白卡住任务（历史：reqCaps 与 roster 能力不匹配的任务卡 120s+
  /// 才被别的成员领走）。否则保持原时间窗语义：reserved 点名缓冲 / matched /
  /// widened 在无在线合格成员时按窗口放宽。
  static RoutingStage nextStage(
    TeamTask t,
    int now, {
    required bool hasEligibleLiveMember,
    required bool hasEligibleEngageableMember,
  }) {
    final hasAny = hasEligibleLiveMember || hasEligibleEngageableMember;
    final r = t.routing;
    final elapsed = now - r.escalatedAt;
    switch (r.stage) {
      case RoutingStage.reserved:
        if (!hasAny) return RoutingStage.matched;
        return elapsed >= r.reserveWindowMs
            ? RoutingStage.matched
            : RoutingStage.reserved;
      case RoutingStage.matched:
        if (!hasAny) return RoutingStage.widened;
        return (!hasEligibleLiveMember && elapsed >= r.widenAfterMs)
            ? RoutingStage.widened
            : RoutingStage.matched;
      case RoutingStage.widened:
        if (!hasAny) return RoutingStage.open;
        return (!hasEligibleLiveMember && elapsed >= r.openAfterMs)
            ? RoutingStage.open
            : RoutingStage.widened;
      case RoutingStage.open:
        return RoutingStage.open;
    }
  }
}
