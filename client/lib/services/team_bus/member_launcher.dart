import 'team_message.dart';

/// TeamBus 调用它来产生两个副作用：物化虚拟成员（拉起 PTY）、门铃唤醒（注入 stdin）。
/// 生产实现委托 ChatCubit/SessionLifecycleService（另起接线 plan）；测试用手写 fake。
abstract interface class MemberLauncher {
  /// 惰性物化：拉起成员 PTY，并把 [bootstrap] 当首个 prompt 注入。
  Future<void> materialize(String memberId, TeamMessage bootstrap);

  /// 门铃：往已 idle 成员的 stdin 注入一条 [notice]（仅提示去 pull，不含真实内容）。
  void wake(String memberId, String notice);

  /// 门铃重试：不重打提示全文，只补一个回车把**已卡在输入框里**的上一条提示提交
  /// （全屏 TUI 输入框偶发把首个回车吞成换行时）。重打全文会让同一条提示在框里叠成
  /// 好几份——这正是 [wake] 不能用于重试的原因。
  void nudgeSubmit(String memberId);
}
