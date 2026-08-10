import 'package:ai_message_core/ai_message_core.dart';

import '../cli_capability.dart';

/// Capability that supplies per-CLI resolver implementations for extracting
/// structured info from tool-call parts: edit hunks, file targets, and shell
/// commands.
///
/// Each CLI tool definition provides its own concrete implementation so that
/// the tool names and argument key conventions match the CLI's actual tool
/// definitions exactly.
abstract interface class ToolCallResolversCapability implements CliCapability {
  AiEditToolTargetResolver get editResolver;
  AiToolFileTargetResolver get fileResolver;
  AiShellToolTargetResolver get shellResolver;
}
