import '../../../services/acp/acp_process_transport.dart';
import '../../../services/acp/acp_transport.dart';

/// One started ACP transport plus the exit future the handshake race needs.
///
/// [processExitCode] is null for transports with no process-like exit status.
typedef AcpStartedTransport = ({
  AcpTransport transport,
  Future<int>? processExitCode,
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
      );
    };
