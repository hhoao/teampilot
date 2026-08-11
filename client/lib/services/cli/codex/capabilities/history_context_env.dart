import '../../registry/capabilities/history_context_env_capability.dart';

final class CodexHistoryContextEnv implements HistoryContextEnvCapability {
  const CodexHistoryContextEnv();
  @override
  Map<String, String> sessionEnv({String? toolRoot}) {
    if (toolRoot == null || toolRoot.isEmpty) return const {};
    return {'CODEX_HOME': toolRoot};
  }
}
