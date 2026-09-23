import 'member_launcher.dart';
import 'member_materializer.dart';
import 'team_message.dart';

export 'member_materializer.dart';

/// 把 TeamBus 的 materialize/wake 接到 ChatCubit 的真实终端启动 / stdin 注入。
class ChatCubitMemberLauncher implements MemberLauncher {
  ChatCubitMemberLauncher({
    required this.materializer,
    required this.sessionId,
  });

  final MemberMaterializer materializer;
  final String sessionId;

  @override
  Future<void> materialize(String memberId, TeamMessage bootstrap) {
    return materializer.materializeMember(
      sessionId,
      memberId,
      bootstrap.content,
    );
  }

  @override
  void wake(String memberId, String notice) {
    materializer.injectMemberStdin(sessionId, memberId, notice);
  }

  @override
  void retryDelivery(String memberId, String notice) {
    materializer.retryDelivery(sessionId, memberId, notice);
  }
}
