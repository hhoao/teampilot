import 'package:path/path.dart' as p;

import '../../registry/capabilities/history_context_env_capability.dart';

final class OpencodeHistoryContextEnv implements HistoryContextEnvCapability {
  const OpencodeHistoryContextEnv();
  @override
  Map<String, String> sessionEnv({String? toolRoot}) {
    if (toolRoot == null || toolRoot.isEmpty) return const {};
    return {'OPENCODE_DB': p.join(toolRoot, 'opencode.db')};
  }
}
