import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../ssh/ssh_forward_channel.dart';
import 'acp_transport.dart';

/// Argv and env the proxy should use to spawn the CLI.
///
/// Carried on the forward transport so `session/new` can put them in
/// `_meta.teampilot`. [env] may hold secrets; do not log it.
class AcpProxyLaunchCarry {
  const AcpProxyLaunchCarry({
    required this.argv,
    required this.env,
    this.authenticateMethodId,
  });

  final List<String> argv;
  final Map<String, String> env;
  final String? authenticateMethodId;
}

/// ACP bytes over an SSH local forward.
///
/// [close] drops the forwarded socket only. It does not signal the proxy or
/// the CLI. Disconnect is not session close.
class AcpProxyForwardTransport implements AcpTransport {
  AcpProxyForwardTransport({
    required SshForwardByteChannel channel,
    required List<String> argv,
    required Map<String, String> env,
  }) : _channel = channel,
       argv = List<String>.unmodifiable(argv),
       env = Map<String, String>.unmodifiable(env) {
    _stderr = StreamController<List<int>>.broadcast();
    _input = StreamController<Uint8List>.broadcast();
    _subscription = _channel.incoming.listen(
      (chunk) => _input.add(Uint8List.fromList(chunk)),
      onError: _input.addError,
      onDone: () {
        if (!_input.isClosed) unawaited(_input.close());
      },
    );
  }

  final SshForwardByteChannel _channel;
  final List<String> argv;
  final Map<String, String> env;

  /// Set by the spawner after it resolves the CLI's authenticate method.
  /// The phone does not send `authenticate` on this transport.
  String? authenticateMethodId;

  late final StreamController<Uint8List> _input;
  late final StreamController<List<int>> _stderr;
  late final StreamSubscription<List<int>> _subscription;
  bool _closed = false;

  AcpProxyLaunchCarry get launch => AcpProxyLaunchCarry(
    argv: argv,
    env: env,
    authenticateMethodId: authenticateMethodId,
  );

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  bool get isClosed => _closed;

  @override
  void write(String frame) {
    if (_closed) return;
    _channel.add(utf8.encode('$frame\n'));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    try {
      await _channel.close();
    } on Object {
      // The forward may already be gone. The proxy process stays up.
    }
    if (!_input.isClosed) await _input.close();
    if (!_stderr.isClosed) await _stderr.close();
  }
}
