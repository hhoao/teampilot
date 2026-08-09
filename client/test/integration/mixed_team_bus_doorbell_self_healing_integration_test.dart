@Tags(['integration', 'cross-platform'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/persistence/in_memory_bus_message_log.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import '../services/team_bus/support/fake_member_launcher.dart';
import 'support/integration_prerequisites.dart';

const _workers = ['architect', 'builder-0', 'builder-1', 'reviewer'];

/// 回归:lead 广播 + 惰性连接的 worker → 全部成员最终消费并 park,
/// 无人被假标为 in-turn(诚实状态:MaterializeCompleted → turnDoneReady,
/// 门铃投递失败也不再让成员永久 stuck active)。
void main() {
  late TeamBus bus;
  late FakeMemberLauncher launcher;

  setUp(() {
    IntegrationPrerequisites.resetHttpOverrides();
    launcher = FakeMemberLauncher();
    bus = TeamBus(
      launcher: launcher,
      messageLog: InMemoryBusMessageLog(),
    );
    bus.declareMember(
      AgentNode.test(
        memberId: 'team-lead',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
        isTeamLead: true,
      ),
    );
    for (final w in _workers) {
      bus.declareMember(
        AgentNode.test(
          memberId: w,
          lifecycle: MemberLifecycle.declared, // 模拟惰性连接:广播前未物化
          activity: MemberActivity.none,
        ),
      );
    }
  });

  test(
    'broadcast to lazily-declared workers: all consume and park, none stuck active',
    () async {
      // 1. lead 广播(materializeDeclared)把 4 个 worker 拉起 → running + turnDoneReady + 各 1 未读。
      await bus.broadcast(
        TeamMessage(
          id: 'greet',
          from: 'team-lead',
          to: '*',
          content: 'hello team',
        ),
        materializeDeclared: true,
      );

      for (final w in _workers) {
        final node = bus.memberById(w)!;
        expect(
          node.lifecycle,
          MemberLifecycle.running,
          reason: '$w materialized',
        );
        expect(
          node.activity,
          MemberActivity.turnDoneReady,
          reason: '$w at-prompt, honest (not optimistically active)',
        );
        expect(node.inbox.isEmpty, isFalse, reason: '$w has unread');
        expect(
          bus.pendingDoorbellNoticeFor(w),
          isNotNull,
          reason: '$w owes a doorbell',
        );
        expect(bus.isMemberInTurn(w), isFalse, reason: '$w not falsely working');
      }

      // 2. 走几轮看门狗(真实环境由 1s idle watch 驱动;这里受 5s doorbellRetryMs
      //    节流约束可能不触发重投,但核心不变量与本步骤无关)。门铃投递健壮性
      //    由单测覆盖;这里验证状态机端到端。
      for (var i = 0; i < 3; i++) {
        bus.reengageIdleWorkers();
      }

      // 3. 每个 worker 消费未读(receiveWork 返回工作后成员按设计 WaitExited →
      //    active 恢复处理;核心不变量是:已消费 + 不再欠门铃,而非 stuck active+未读)。
      for (final w in _workers) {
        final batch = await bus.receiveWork(w);
        expect(batch, isA<MessageWork>(), reason: '$w consumes the greeting');
        final node = bus.memberById(w)!;
        expect(node.inbox.isEmpty, isTrue, reason: '$w consumed all mail');
        expect(
          bus.pendingDoorbellNoticeFor(w),
          isNull,
          reason: '$w no longer owes a doorbell',
        );
      }
    },
  );
}
