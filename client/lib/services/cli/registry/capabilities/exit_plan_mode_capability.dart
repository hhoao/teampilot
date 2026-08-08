import '../cli_capability.dart';

/// How a CLI resolves an in-chat ExitPlanMode approval.
enum ExitPlanApprovalKind { hookReply, none }

/// Per-CLI support for approving/rejecting `ExitPlanMode` in chat.
///
/// claude + flashskyai hold the `PreToolUse` HTTP hook and reply with the
/// official `permissionDecision`. Other CLIs keep the "Open Terminal" fallback.
abstract interface class ExitPlanModeCapability implements CliCapability {
  bool get supportsInChatApproval;
  ExitPlanApprovalKind get approvalKind;
}

final class HookExitPlanModeCapability implements ExitPlanModeCapability {
  const HookExitPlanModeCapability();

  @override
  bool get supportsInChatApproval => true;

  @override
  ExitPlanApprovalKind get approvalKind => ExitPlanApprovalKind.hookReply;
}

final class NoExitPlanModeCapability implements ExitPlanModeCapability {
  const NoExitPlanModeCapability();

  @override
  bool get supportsInChatApproval => false;

  @override
  ExitPlanApprovalKind get approvalKind => ExitPlanApprovalKind.none;
}
