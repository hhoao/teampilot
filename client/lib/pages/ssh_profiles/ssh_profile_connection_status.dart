import '../../cubits/ssh_connection_cubit.dart' show SshHostUiStatus;
export '../../cubits/ssh_connection_cubit.dart' show SshHostUiStatus;

/// Shared UI status for SSH profile cards and the status-bar host list.
///
/// Prefer [SshHostUiStatus] in new code; this typedef keeps existing config
/// card call sites compiling during the Task 7 migration.
typedef SshProfileConnectionStatus = SshHostUiStatus;
