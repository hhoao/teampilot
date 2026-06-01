import 'member_launcher.dart';
import 'team_message.dart';

/// ChatCubit 暴露给 launcher 的最小 seam（便于测试注入，避免泄漏 _InternalTab）。
abstract interface class MemberMaterializer {
  Future<void> materializeMember(String sessionId, String memberId, String bootstrap);
  void injectMemberStdin(String sessionId, String memberId, String text);
}

/// 把 TeamBus 的 materialize/wake 接到 ChatCubit 的真实终端启动 / stdin 注入。
class ChatCubitMemberLauncher implements MemberLauncher {
  ChatCubitMemberLauncher({required this.materializer, required this.sessionId});

  final MemberMaterializer materializer;
  final String sessionId;

  @override
  Future<void> materialize(String memberId, TeamMessage bootstrap) {
    return materializer.materializeMember(sessionId, memberId, bootstrap.content);
  }

  @override
  void wake(String memberId, String notice) {
    materializer.injectMemberStdin(sessionId, memberId, notice);
  }
}
