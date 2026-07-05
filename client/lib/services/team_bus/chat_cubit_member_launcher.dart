import 'member_launcher.dart';
import 'team_message.dart';

/// ChatCubit 暴露给 launcher 的最小 seam（便于测试注入，避免泄漏 _InternalTab）。
abstract interface class MemberMaterializer {
  Future<void> materializeMember(
    String sessionId,
    String memberId,
    String bootstrap,
  );
  void injectMemberStdin(String sessionId, String memberId, String text);

  /// 只提交输入框里已有内容（补回车）。由 [retryDelivery] 在扫屏确认已贴上后调用。
  void submitMemberPending(String sessionId, String memberId);

  /// 扫屏后决定补 CR 还是重新粘贴 [notice]。
  void retryDelivery(String sessionId, String memberId, String notice);
}

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
  void nudgeSubmit(String memberId) {
    materializer.submitMemberPending(sessionId, memberId);
  }

  @override
  void retryDelivery(String memberId, String notice) {
    materializer.retryDelivery(sessionId, memberId, notice);
  }
}
