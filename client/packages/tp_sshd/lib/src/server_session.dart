import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/protocol.dart'
    show SSHChannelRequestType, SSH_Message_Channel_Request;

import 'server_channel.dart';
import 'server_process.dart';
import 'server_sftp.dart';
import 'ssh_server.dart' show SSHServerConfig;

/// Session state accumulated across the requests of one channel, keyed off
/// the channel itself so it lives and dies with it.
final Expando<_SessionState> _sessionStates = Expando();

/// Serves session channel requests (RFC 4254 §6) on one open channel.
///
/// Two grammars are spoken, one per channel:
///
/// * the structured `tp1:` exec payload ([TpExecCodec]) — the host-info
///   query inside it is answered by the server itself, and anything else in
///   that grammar is handed to [SSHServerConfig.processFactory];
/// * the interactive half — `env` requests accumulate, `pty-req` stashes the
///   terminal dimensions, and `shell` spawns the pty through
///   [SSHServerConfig.ptyFactory], after which `window-change` resizes it
///   and `signal` delivers signals to it;
/// * the `sftp` subsystem — served by the SFTPv3 server over
///   [SSHServerConfig.sftpFileSystem] (see [serveSftpSubsystem]).
///
/// A channel takes exactly one lifecycle request, `exec`, `shell` or the
/// `sftp` subsystem
/// (RFC 4254 §6.5's session channels are single-use): a second one is
/// refused and the channel closed. `shell` additionally requires a prior
/// `pty-req` — this server only serves pty sessions. A plain shell-string
/// command is not the exec grammar: it is refused and the channel is
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
  final state = _sessionStates[channel] ??= _SessionState();
  switch (request.requestType) {
    case SSHChannelRequestType.pty:
      return _handlePtyRequest(state, request);
    case SSHChannelRequestType.env:
      return _handleEnvRequest(state, request);
    case SSHChannelRequestType.windowChange:
      return _handleWindowChange(state, request);
    case SSHChannelRequestType.signal:
      return _handleSignalRequest(state, request);
    case SSHChannelRequestType.exec:
      return _serveExec(channel, request, config: config, state: state);
    case SSHChannelRequestType.shell:
      return _serveShell(channel, config: config, state: state);
    case SSHChannelRequestType.subsystem:
      return _serveSubsystem(channel, request, config: config, state: state);
    default:
      return false;
  }
}

/// State one session channel accumulates between its requests.
class _SessionState {
  /// Dimensions stashed by `pty-req`, kept current with any `window-change`
  /// that arrives before the shell consumes them.
  SSHPtyDimensions? ptyDimensions;

  /// Variables accumulated from `env` requests, merged into the pty
  /// environment when the shell starts.
  final Map<String, String> environment = {};

  /// The pty serving a started shell, if any — the target of the channel's
  /// later `window-change` and `signal` requests.
  SSHServerPty? pty;

  /// Whether this channel already took its one lifecycle request.
  var lifecycleClaimed = false;
}

/// Stashes the terminal dimensions of a `pty-req` (RFC 4254 §6.2) for the
/// shell request that follows. The terminal type rides along as `TERM`; the
/// encoded terminal modes are not parsed.
bool _handlePtyRequest(
    _SessionState state, SSH_Message_Channel_Request request) {
  final termType = request.termType;
  if (termType == null) return false;
  state.ptyDimensions = SSHPtyDimensions(
    columns: request.termWidth ?? 80,
    rows: request.termHeight ?? 24,
    pixelWidth: request.termPixelWidth ?? 0,
    pixelHeight: request.termPixelHeight ?? 0,
    environment: {'TERM': termType},
  );
  return true;
}

/// Accumulates one `env` request (RFC 4254 §6.4) into the environment the
/// shell will start with.
bool _handleEnvRequest(
    _SessionState state, SSH_Message_Channel_Request request) {
  final name = request.variableName;
  final value = request.variableValue;
  if (name == null || value == null) return false;
  state.environment[name] = value;
  return true;
}

/// Applies a `window-change` (RFC 4254 §6.7): resizes the running pty. With
/// no live pty on the channel the request is refused — an honest failure
/// rather than a success ack for a resize nothing received — though the
/// dimensions stashed by `pty-req` are still refreshed, so a shell request
/// that arrives afterwards starts at the size the client last announced.
bool _handleWindowChange(
  _SessionState state,
  SSH_Message_Channel_Request request,
) {
  final columns = request.termWidth;
  final rows = request.termHeight;
  if (columns == null || rows == null) return false;
  final pty = state.pty;
  if (pty != null) {
    pty.resize(columns, rows);
    return true;
  }
  final dimensions = state.ptyDimensions;
  if (dimensions != null) {
    state.ptyDimensions = SSHPtyDimensions(
      columns: columns,
      rows: rows,
      pixelWidth: request.termPixelWidth ?? dimensions.pixelWidth,
      pixelHeight: request.termPixelHeight ?? dimensions.pixelHeight,
      environment: dimensions.environment,
    );
  }
  return false;
}

/// Delivers a `signal` request (RFC 4254 §6.9) to the running pty by the
/// name the client sent — the fork's client emits the RFC names directly
/// from its `SSHSignal` enum, so they pass through unchanged. With no live
/// pty there is nothing to deliver the signal to, and the request is
/// refused instead of acknowledged as a silent no-op.
bool _handleSignalRequest(
  _SessionState state,
  SSH_Message_Channel_Request request,
) {
  final name = request.signalName;
  if (name == null) return false;
  final pty = state.pty;
  if (pty == null) return false;
  pty.signal(name);
  return true;
}

/// Serves the structured `exec` request (see [TpExecCodec]).
Future<bool> _serveExec(
  SSHServerChannel channel,
  SSH_Message_Channel_Request request, {
  required SSHServerConfig config,
  required _SessionState state,
}) async {
  if (!_claimLifecycle(channel, state)) return false;

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

/// Serves the `shell` request (RFC 4254 §6.5): requires the `pty-req`
/// stashed earlier on the channel, then spawns the pty with those
/// dimensions and the accumulated `env` variables, and pipes it like an
/// exec.
Future<bool> _serveShell(
  SSHServerChannel channel, {
  required SSHServerConfig config,
  required _SessionState state,
}) async {
  if (!_claimLifecycle(channel, state)) return false;

  final dimensions = state.ptyDimensions;
  // This server only serves pty sessions; a shell without a pty-req has
  // nothing to spawn the pty with.
  if (dimensions == null) return false;
  final ptyFactory = config.ptyFactory;
  if (ptyFactory == null) return false;

  final initial = SSHPtyDimensions(
    columns: dimensions.columns,
    rows: dimensions.rows,
    pixelWidth: dimensions.pixelWidth,
    pixelHeight: dimensions.pixelHeight,
    environment: {...dimensions.environment, ...state.environment},
  );
  final SSHServerPty pty;
  try {
    final spawned = await ptyFactory(initial);
    if (spawned == null) return false;
    pty = spawned;
  } on Object {
    // A misbehaving factory is a refused request, not a dead connection.
    return false;
  }

  state.pty = pty;
  _afterReply(channel, () => _pipeProcess(channel, pty));
  return true;
}

/// Serves the `subsystem` request (RFC 4254 §6.5): the only subsystem this
/// server speaks is `sftp`, and only over a configured filesystem
/// ([SSHServerConfig.sftpFileSystem]). Anything else is refused.
Future<bool> _serveSubsystem(
  SSHServerChannel channel,
  SSH_Message_Channel_Request request, {
  required SSHServerConfig config,
  required _SessionState state,
}) async {
  if (!_claimLifecycle(channel, state)) return false;
  final filesystem = config.sftpFileSystem;
  if (request.subsystemName != 'sftp' || filesystem == null) return false;
  _afterReply(
    channel,
    () => serveSftpSubsystem(channel, filesystem: filesystem),
  );
  return true;
}

/// Claims the channel's one lifecycle request (`exec`, `shell` or the `sftp`
/// subsystem). A session
/// channel serves a single program (RFC 4254 §6.5); a second lifecycle
/// request is refused, and the channel is closed once that failure reply is
/// on the wire.
bool _claimLifecycle(SSHServerChannel channel, _SessionState state) {
  if (state.lifecycleClaimed) {
    _afterReply(channel, channel.close);
    return false;
  }
  state.lifecycleClaimed = true;
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
  ];
  StreamSubscription<Uint8List>? inputSubscription;
  inputSubscription = channel.input.listen(
    (data) {
      try {
        process.stdin.add(data);
      } on Object {
        // The process's stdin contract broke mid-write (a pipe the process
        // already tore down, a sink that fails closed): treat it as the
        // input side ending — stop forwarding input to it and release the
        // pipe — instead of letting the error escape into the stream
        // listener's zone.
        inputSubscription?.cancel();
        unawaited(process.stdin.close().catchError((_) {}));
      }
    },
    onDone: () => unawaited(process.stdin.close().catchError((_) {})),
  );
  subscriptions.add(inputSubscription);

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
    unawaited(process.stdin.close().catchError((_) {}));
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
    }).catchError((Object _) {
      // A process contract that errors instead of exiting is process death
      // all the same: tear the pipes down and finish the channel without an
      // exit status, rather than orphaning it on a future that never
      // settles.
      teardown();
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
