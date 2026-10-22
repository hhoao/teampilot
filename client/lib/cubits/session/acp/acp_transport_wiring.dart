import '../../../models/app_session.dart';
import '../../../models/runtime_target.dart';
import '../../../models/ssh_profile.dart';
import '../../../services/acp/acp_process_transport.dart';
import '../../../services/acp/acp_ssh_transport.dart';
import '../../../services/acp/acp_transport.dart';
import '../../../services/chat/launch/connect/chat_session_shell_factory.dart';

/// One started ACP transport plus the exit future the handshake race needs.
///
/// [processExitCode] is null for transports with no process-like exit status.
/// [pid] is the local agent OS pid for process-backed transports, null for SSH
/// / in-memory ones; it feeds the Resource Manager metrics registry.
typedef AcpStartedTransport = ({
  AcpTransport transport,
  Future<int>? processExitCode,
  int? pid,
});

/// Starts one ACP agent transport for an argv + env candidate.
///
/// `workingDirectory` (and, for SSH, the member session) is captured by the
/// starter closure — the same shape as `productionAcpSpawner`, which captures
/// cwd too. This is the local-vs-remote fork point.
typedef AcpTransportStarter =
    Future<AcpStartedTransport> Function({
      required List<String> argv,
      required Map<String, String> env,
      required String workingDirectory,
      void Function(List<int>)? onStderr,
    });

/// Local desktop process transport (unchanged pre-remote behavior).
AcpTransportStarter localAcpTransportStarter() =>
    ({
      required List<String> argv,
      required Map<String, String> env,
      required String workingDirectory,
      void Function(List<int>)? onStderr,
    }) async {
      final transport = await AcpProcessTransport.start(
        executable: argv.first,
        args: argv.skip(1).toList(),
        environment: env,
        workingDirectory: workingDirectory,
        onStderr: onStderr,
      );
      return (
        transport: transport,
        processExitCode: transport.processExitCode,
        pid: transport.pid,
      );
    };

/// Builds the remote shell command for one ACP argv candidate.
///
/// Empty env values are dropped: the local transport removes them so a
/// set-but-empty `ANTHROPIC_API_KEY` is *unset*, but the remote command builder
/// exports whatever it is given. Passing `K=''` would flip Claude into API-key
/// mode with no key ("Not logged in"), so filter first.
///
/// No login shell: `.bashrc` banners would corrupt the NDJSON stdout channel.
/// The legacy codec still exports the managed Node path and `~/.local/bin`,
/// which covers the agent/adapter binary.
String buildAcpRemoteCommand({
  required SshProfile profile,
  required List<String> argv,
  required String workingDirectory,
  required Map<String, String> env,
}) {
  final cleaned = <String, String>{
    for (final entry in env.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value,
  };
  return ChatSessionShellFactory.buildMemberRemoteCommand(
    profile: profile,
    executable: argv.first,
    arguments: argv.skip(1).toList(),
    remoteWorkingDirectory: workingDirectory,
    environment: cleaned.isEmpty ? null : cleaned,
    useLoginShell: false,
  );
}

/// Opens one SSH exec channel for a command. Production wraps
/// `SshMemberSession.openExec` in [DartSsh2AcpChannel]; tests inject a fake.
typedef AcpSshChannelOpener = Future<AcpSshChannel> Function(String command);

/// Remote transport over one SSH member session.
AcpTransportStarter sshAcpTransportStarter({
  required SshProfile profile,
  required AcpSshChannelOpener openChannel,
}) =>
    ({
      required List<String> argv,
      required Map<String, String> env,
      required String workingDirectory,
      void Function(List<int>)? onStderr,
    }) async {
      final command = buildAcpRemoteCommand(
        profile: profile,
        argv: argv,
        workingDirectory: workingDirectory,
        env: env,
      );
      final channel = await openChannel(command);
      final transport = AcpSshTransport(channel: channel, onStderr: onStderr);
      return (
        transport: transport,
        processExitCode: transport.processExitCode,
        pid: null,
      );
    };

/// Everything the remote ACP starter needs: the SSH profile (for command
/// encoding) and a lazy channel opener.
typedef AcpSshLaunch = ({
  SshProfile profile,
  AcpSshChannelOpener openChannel,
});

/// Builds one [AcpSshLaunch] for a session + target. Production opens (and
/// stores on the tab) the member SSH session; tests inject a fake.
typedef AcpSshLaunchFactory = AcpSshLaunch Function({
  required AppSession session,
  required RuntimeTarget launchTarget,
});

/// Null → the spawner's local process starter. Non-null → the SSH starter.
///
/// A remote target without an [AcpSshLaunch] is a wiring bug, not a fallback:
/// failing loudly avoids silently spawning a local process for a remote
/// workspace (the pre-Phase-1 behavior).
AcpTransportStarter? acpStarterForTarget({
  required RuntimeTarget launchTarget,
  AcpSshLaunch? sshLaunch,
}) {
  if (!usesSshTransport(launchTarget.kind)) return null;
  final launch = sshLaunch;
  if (launch == null) {
    throw StateError(
      'Remote ACP launch requires an SSH launch (profile + channel opener)',
    );
  }
  return sshAcpTransportStarter(
    profile: launch.profile,
    openChannel: launch.openChannel,
  );
}
