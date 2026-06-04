import '../member_state.dart';

/// 成员在线态的不可变值:`MemberLifecycle`（PTY）× `MemberActivity`（CLI/bus）。
/// [PresenceReducer] 在它之上做纯函数跃迁。
class Presence {
  const Presence(this.lifecycle, this.activity);

  const Presence.declared()
    : lifecycle = MemberLifecycle.declared,
      activity = MemberActivity.none;

  final MemberLifecycle lifecycle;
  final MemberActivity activity;

  bool get ptyRunning =>
      lifecycle == MemberLifecycle.materializing ||
      lifecycle == MemberLifecycle.running;

  bool get isParked => activity == MemberActivity.turnDoneBusWait;

  bool get atPrompt =>
      lifecycle == MemberLifecycle.running &&
      activity == MemberActivity.turnDoneReady;

  Presence copyWith({MemberLifecycle? lifecycle, MemberActivity? activity}) =>
      Presence(lifecycle ?? this.lifecycle, activity ?? this.activity);

  @override
  bool operator ==(Object other) =>
      other is Presence &&
      other.lifecycle == lifecycle &&
      other.activity == activity;

  @override
  int get hashCode => Object.hash(lifecycle, activity);

  @override
  String toString() => 'Presence(${lifecycle.name}, ${activity.name})';
}
