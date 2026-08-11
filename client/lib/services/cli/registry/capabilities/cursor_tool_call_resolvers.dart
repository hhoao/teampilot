import 'package:ai_message_core/ai_message_core.dart';

import '../../../ai_history/tool_call_resolvers.dart';
import 'shared_tool_call_resolvers.dart';

/// Cursor tool-call resolvers: shared configuration plus `execute` as a shell
/// / terminal tool name.
class CursorToolCallResolvers extends SharedToolCallResolvers {
  const CursorToolCallResolvers();

  @override
  AiShellToolTargetResolver get shellResolver =>
      const ConfigurableAiShellToolTargetResolver(
        toolNames: {
          'bash',
          'shell',
          'execute',
          'run_terminal_cmd',
          'shell_command',
          'exec_command',
          'run_shell_command',
        },
      );
}
