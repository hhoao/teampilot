/// TeamBus 成员状态：`MemberLifecycle`（PTY）× `MemberActivity`（CLI/bus）。
///
/// Mermaid 流程图见仓库 [TEAM_BUS_MEMBER_STATE.md](../../../../docs/TEAM_BUS_MEMBER_STATE.md)。
///
/// PTY / 进程是否存在（TeamPilot 扩展；Claude spawn 时通常直接 running）。
enum MemberLifecycle {
  /// 已在 roster，CLI 未 spawn（mixed 惰性启动）。
  declared,

  /// 正在 spawn PTY + 注入 bootstrap。
  materializing,

  /// PTY 已起来。
  running,
}

/// CLI / bus 活动态。
///
/// - [active] ↔ Claude `isActive: true`
/// - [turnDoneReady] / [turnDoneBusWait] / [mailQueued] ↔ `isActive: false`（turn 已结束一侧）
enum MemberActivity {
  /// 尚无 PTY（declared）且信箱无积压。
  none,

  /// turn 进行中（Claude `isActive: true`）。
  active,

  /// turn 已结束：在 prompt，尚未进入 bus `wait_for_message`。
  turnDoneReady,

  /// turn 已结束：PTY 运行中，正阻塞在 MCP `wait_for_message`。
  turnDoneBusWait,

  /// 尚无 PTY（declared），信箱有积压、等物化。
  mailQueued,
}

/// [MemberActivity] 语义与 MCP/UI 展示标签。
extension MemberActivitySemantics on MemberActivity {
  /// Claude `TeamFile.members[].isActive`.
  bool get claudeIsActive => this == MemberActivity.active;

  /// turn 已结束（含等信）；Claude 侧均为 idle。
  bool get isTurnDone => switch (this) {
    MemberActivity.turnDoneReady ||
    MemberActivity.turnDoneBusWait ||
    MemberActivity.mailQueued =>
      true,
    _ => false,
  };

  /// MCP `wait_for_message` 已阻塞（仅 running + 此态）。
  bool get isBusWaitBlocked => this == MemberActivity.turnDoneBusWait;

  /// 无 PTY，邮件已排队、等 spawn。
  bool get isMailQueuedWithoutPty => this == MemberActivity.mailQueued;

  /// 任一「在等 teammate 信」形态。
  bool get isWaitingForMail => isBusWaitBlocked || isMailQueuedWithoutPty;

  /// `list_teammates` 合成态（`turn_done` 前缀消除 at_prompt / idleWaiting 歧义）。
  String get busPhaseLabel => switch (this) {
    MemberActivity.none => 'offline',
    MemberActivity.active => 'in_turn',
    MemberActivity.turnDoneReady => 'turn_done · ready',
    MemberActivity.turnDoneBusWait => 'turn_done · bus_wait',
    MemberActivity.mailQueued => 'no_pty · mail_queued',
  };
}
