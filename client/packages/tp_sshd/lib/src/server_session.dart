import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/protocol.dart'
    show SSHChannelRequestType, SSH_Message_Channel_Request;

import 'server_channel.dart';
import 'server_process.dart';
import 'ssh_server.dart' show SSHServerConfig;

/// Serves session channel requests (RFC 4254 §6) on one open channel.
///
/// `exec` is the only request type served so far, and it speaks exactly one
/// grammar: the structured `tp1:` payload ([TpExecCodec]). The host-info
/// query inside that grammar is answered by the server itself. A plain
/// shell-string command is not the grammar: it is refused and the channel is
/// closed — this server never hands a raw command line to a shell.
///
/// The returned future is the request outcome [SSHServerChannel.onRequest]
/// replies with: `true` acknowledges the request, `false` refuses it. The
/// reply is sent once this future settles; the serving that follows (streamed
/// output, exit-status, close) is scheduled behind it via [_afterReply].
Future<bool> handleSessionRequest(
  SSHServerChannel channel,
  SSH_Message_Channel_Request request, {
  required SSHServerConfig config,
}) async {
  if (request.requestType != SSHChannelRequestType.exec) return false;
  final command = request.command;
  if (command == null) return false;

  if (TpExecCodec.isHostInfoQuery(command)) {
    return _serveHostInfoQuery(channel, config);
  }

  final exec = TpExecCodec.tryDecode(command);
  if (exec == null) {
    // Not this server's grammar (a plain shell string, or a malformed
    // payload): refuse the request, then close the channel once the failure
    // reply is on the wire.
    _afterReply(channel, channel.close);
    return false;
  }

  final processFactory = config.processFactory;
  if (processFactory == null) return false;
  final SSHServerProcess process;
  try {
    final spawned = await processFactory(exec.argv, exec.cwd, exec.env);
    if (spawned == null) return false;
    process = spawned;
  } on Object {
    // A misbehaving factory is a refused request, not a dead connection.
    return false;
  }

  _afterReply(channel, () => _pipeProcess(channel, process));
  return true;
}

/// Answers the host-info query from [SSHServerConfig.hostInfo]: writes the
/// JSON snapshot to stdout, reports exit 0, and finishes the channel. No
/// process is ever spawned for it.
Future<bool> _serveHostInfoQuery(
  SSHServerChannel channel,
  SSHServerConfig config,
) async {
  final hostInfo = config.hostInfo?.call();
  if (hostInfo == null) return false;
  _afterReply(channel, () {
    channel.write(
      Uint8List.fromList(utf8.encode(TpExecCodec.encodeHostInfo(hostInfo))),
    );
    channel.sendExitStatus(0);
    channel.close();
  });
  return true;
}

/// Wires a spawned process to its channel for the rest of the exec.
///
/// stdout is written as channel data, stderr as extended data, and channel
/// input is piped to the process's stdin. When the process exits, its exit
/// status is reported first (RFC 4254 §6.10 — exit-status strictly before
/// EOF and close). When the channel ends first — the client went away, or
/// the connection was torn down — the process is killed and its streams are
/// closed, so nothing is orphaned.
void _pipeProcess(SSHServerChannel channel, SSHServerProcess process) {
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  StreamSubscription<Uint8List> drain(
    Stream<Uint8List> stream,
    void Function(Uint8List data) write,
    Completer<void> done,
  ) =>
      stream.listen(
        write,
        // An erroring pipe counts as drained: the exit status still needs to
        // be reported after whatever output made it through.
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );

  final subscriptions = <StreamSubscription<dynamic>>[
    drain(process.stdout, channel.write, stdoutDone),
    drain(process.stderr, channel.writeExtended, stderrDone),
    channel.input.listen(
      process.stdin.add,
      onDone: () => unawaited(process.stdin.close()),
    ),
  ];

  var tornDown = false;
  void teardown() {
    if (tornDown) return;
    tornDown = true;
    process.kill();
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    // Unblock the exit-status continuation too, so it cannot wait forever on
    // pipes a cancelled subscription will never finish.
    if (!stdoutDone.isCompleted) stdoutDone.complete();
    if (!stderrDone.isCompleted) stderrDone.complete();
    unawaited(process.stdin.close());
  }

  channel.done.whenComplete(teardown);

  unawaited(
    process.exitCode.then((exitCode) async {
      // Let the pipes drain first: the exit status must not overtake output
      // that is still in flight.
      await stdoutDone.future;
      await stderrDone.future;
      channel.sendExitStatus(exitCode);
      channel.close();
    }),
  );
}

/// Runs [action] after the reply to the request currently being dispatched
/// has been sent.
///
/// [SSHServerChannel.onRequest] hooks settle their request by completing the
/// returned future, and the channel sends the CHANNEL_SUCCESS /
/// CHANNEL_FAILURE reply in the microtask that resumes then. A timer turn is
/// guaranteed to run after every already-scheduled microtask, so work
/// scheduled here lands strictly after that reply: output reaches the client
/// after the answer to the request that produced it, and a refusal can close
/// the channel without suppressing its own failure reply.
void _afterReply(SSHServerChannel channel, void Function() action) {
  if (channel.isClosed) return;
  unawaited(Future<void>.delayed(Duration.zero, action));
}
