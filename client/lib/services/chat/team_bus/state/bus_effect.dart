import '../team_message.dart';

/// 总线产出的副作用,**以数据表达**(而非直接调 launcher)。由 [BusEffectDispatcher]
/// 在边界落地成真实的 PTY 拉起 / stdin 注入。策略(何时)与机制(怎么)解耦,核心
/// 状态机因此可纯函数化、可零 fake 测试。
sealed class BusEffect {
  const BusEffect();
}

/// 门铃:往已 idle 成员的 stdin 注入「有未读」提示(不含真实内容)。
class DoorbellEffect extends BusEffect {
  const DoorbellEffect(this.memberId);
  final String memberId;
}

/// 惰性物化:拉起成员 PTY,并把 [bootstrap] 当首个 prompt 注入。
class MaterializeEffect extends BusEffect {
  const MaterializeEffect(this.memberId, this.bootstrap);
  final String memberId;
  final TeamMessage bootstrap;
}
