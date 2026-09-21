import 'dart:async';

import 'package:teampilot/models/mcp_probe_snapshot.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/services/mcp/mcp_probe_handshake.dart';

class FakeMcpProbeHandshake implements McpProbeHandshake {
  FakeMcpProbeHandshake({
    this.delay = Duration.zero,
    this.abortDelay = Duration.zero,
    this.resultBuilder,
  });

  Duration delay;
  Duration abortDelay;
  McpHandshakeResult Function(McpServer server)? resultBuilder;
  final calledIds = <String>[];
  final abortedKeys = <String>[];
  final listToolsStartedAt = <String, DateTime>{};
  final abortFinishedAt = <String, DateTime>{};
  var inFlight = 0;
  var maxInFlight = 0;
  var closeAllCount = 0;

  @override
  Future<McpHandshakeResult> listTools(
    McpServer server, {
    required String probeKey,
  }) async {
    calledIds.add(server.id);
    listToolsStartedAt[server.id] = DateTime.now();
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      return resultBuilder?.call(server) ??
          McpHandshakeResult.ok(const [McpProbeTool(name: 'health_check')]);
    } finally {
      inFlight--;
    }
  }

  @override
  Future<void> abort(String probeKey) async {
    abortedKeys.add(probeKey);
    if (abortDelay > Duration.zero) {
      await Future<void>.delayed(abortDelay);
    }
    abortFinishedAt[probeKey] = DateTime.now();
  }

  @override
  Future<void> closeAll() async {
    closeAllCount++;
  }
}
