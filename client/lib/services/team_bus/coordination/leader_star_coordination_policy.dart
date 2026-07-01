import '../env/bus_environment.dart';
import '../idle_notification.dart';
import '../team_message.dart';
import 'coordination_policy.dart';

/// 默认拓扑:**星型**——worker 完成一批派活、idle 时向 team-lead 上报一次
/// `idle_notification`,leader 自身永不上报。
///
/// 「每批派活只上报一次」由内部 [_unreported] 集合门控:刚启动从未派活的 worker
/// 不会 ping leader(因而也不会响门铃);忙碌 worker 在再次被派活前不会每个 idle
/// 边重复 ping。
class LeaderStarCoordinationPolicy implements CoordinationPolicy {
  LeaderStarCoordinationPolicy({required BusEnvironment environment})
    : _env = environment;

  final BusEnvironment _env;
  final Set<String> _unreported = {};

  @override
  void noteInboundWork(String memberId) => _unreported.add(memberId);

  @override
  void markIdleReported(String memberId) => _unreported.remove(memberId);

  @override
  List<TeamMessage> onMemberIdle(CoordinationView view, String memberId) {
    final worker = view.member(memberId);
    if (worker == null || worker.profile.isTeamLead) return const [];
    if (!_unreported.contains(memberId)) return const [];
    final leaderId = view.teamLeadId;
    if (leaderId == null || leaderId == memberId) return const [];

    _unreported.remove(memberId);

    final body = IdleNotification.fromWorker(
      memberId: memberId,
      displayName: worker.profile.effectiveDisplayName,
      timestampMs: _env.clock(),
    ).encode();
    return [
      TeamMessage(
        id: _env.ids(),
        from: memberId,
        to: leaderId,
        content: body,
      ),
    ];
  }
}
