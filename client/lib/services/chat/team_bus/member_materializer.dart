/// ChatCubit 暴露给 launcher 的最小 seam（便于测试注入，避免泄漏内部 tab 类型）。
abstract interface class MemberMaterializer {
  Future<void> materializeMember(
    String sessionId,
    String memberId,
    String bootstrap,
  );
  void injectMemberStdin(String sessionId, String memberId, String text);

  /// 扫屏后决定补 CR 还是重新粘贴 [notice]。
  void retryDelivery(String sessionId, String memberId, String notice);
}
