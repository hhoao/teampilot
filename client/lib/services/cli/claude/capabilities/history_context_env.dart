import '../../registry/capabilities/history_context_env_capability.dart';

final class NoHistoryContextEnv implements HistoryContextEnvCapability {
  const NoHistoryContextEnv();
  @override Map<String, String> sessionEnv({String? toolRoot, String? home, String? userProfile}) => const {};
}
