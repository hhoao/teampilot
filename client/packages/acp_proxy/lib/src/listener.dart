import 'dart:io';

import 'package:acpd_io/acpd_io.dart';

import 'advertisement.dart';
import 'proxy_agent.dart';
import 'version.dart';

/// One TCP port on `127.0.0.1` for each CLI id.
///
/// There is no bind-address parameter. [start] writes
/// `<root>/acp-proxy/acp-proxy.pid` before `acp-proxy.json`, so a reader of
/// the advertisement never sees a port without a pid. [close] closes the
/// listening sockets and does not close CLI upstreams.
class AcpProxyListener {
  AcpProxyListener({
    required this.root,
    required this.cliIds,
    required this.agentForCli,
    this.pid,
  });

  final Directory root;
  final List<String> cliIds;
  final AcpProxyAgent Function(String cliId) agentForCli;
  final int? pid;

  final List<ServerSocket> _servers = [];
  var _started = false;

  /// Binds one loopback socket per CLI id and returns the advertisement
  /// written for those ports.
  ///
  /// Throws [ArgumentError] when [pid] is null.
  Future<AcpProxyAdvertisement> start() async {
    final pid = this.pid;
    if (pid == null) {
      throw ArgumentError.notNull('pid');
    }
    if (_started) {
      throw StateError('AcpProxyListener is already started');
    }
    final bound = <_BoundCli>[];
    try {
      for (final cliId in cliIds) {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        bound.add(
          _BoundCli(cliId: cliId, server: server, agent: agentForCli(cliId)),
        );
      }
      await _writePid(pid);
      final advertisement = AcpProxyAdvertisement(
        version: acpProxyVersion,
        pid: pid,
        ports: {for (final entry in bound) entry.cliId: entry.server.port},
      );
      await writeAcpProxyAdvertisement(root, advertisement);
      for (final entry in bound) {
        entry.server.listen(
          (socket) => _serve(entry.cliId, entry.agent, socket),
          // An accept error on one CLI must not stop the other ports.
          onError: (Object _, StackTrace _) {},
        );
      }
      _servers.addAll([for (final entry in bound) entry.server]);
      _started = true;
      return advertisement;
    } catch (error, stackTrace) {
      for (final entry in bound) {
        try {
          await entry.server.close();
        } catch (_) {}
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Closes every listening socket. Accepted phone sockets and CLI upstreams
  /// stay open.
  Future<void> close() async {
    _started = false;
    final servers = List<ServerSocket>.of(_servers);
    _servers.clear();
    for (final server in servers) {
      await server.close();
    }
  }

  Future<void> _writePid(int pid) async {
    final directory = Directory('${root.path}/acp-proxy');
    await directory.create(recursive: true);
    final file = File('${directory.path}/acp-proxy.pid');
    await file.writeAsString('$pid\n', flush: true);
  }
}

void _serve(String cliId, AcpProxyAgent agent, Socket socket) {
  socket.setOption(SocketOption.tcpNoDelay, true);
  final transport = StdioTransport(
    name: 'acp-proxy:$cliId',
    input: socket,
    writeOutput: socket.add,
    onClose: () => _closeAccepted(socket),
  );
  agent.serve(transport);
}

Future<void> _closeAccepted(Socket socket) async {
  try {
    await socket.flush();
  } catch (_) {}
  try {
    await socket.close();
  } catch (_) {}
}

class _BoundCli {
  _BoundCli({required this.cliId, required this.server, required this.agent});

  final String cliId;
  final ServerSocket server;
  final AcpProxyAgent agent;
}
