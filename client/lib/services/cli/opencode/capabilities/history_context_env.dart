import '../../registry/capabilities/history_context_env_capability.dart';

final class OpencodeHistoryContextEnv implements HistoryContextEnvCapability {
  const OpencodeHistoryContextEnv();
  @override
  Map<String, String> sessionEnv({String? toolRoot, String? home, String? userProfile}) {
    if (toolRoot == null || toolRoot.isEmpty) return const {};
    return {'OPENCODE_DB': toolRoot};
  }
}
