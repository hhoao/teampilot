import 'dart:async';

import '../../models/mcp_probe_snapshot.dart';
import '../../models/mcp_server.dart';
import '../../utils/logging/logger.dart';
import 'mcp_probe_handshake.dart';

class McpServerProbeService {
  McpServerProbeService({
    required McpProbeHandshake handshake,
    this.maxConcurrent = 3,
    this.timeout = const Duration(seconds: 15),
  }) : _handshake = handshake;

  final McpProbeHandshake _handshake;
  final int maxConcurrent;
  final Duration timeout;

  final _generations = <String, int>{};
  var _active = 0;
  final _waiters = <Completer<void>>[];
  var _closed = false;

  Future<void> probeEnabled(
    List<McpServer> servers, {
    required void Function(String id, McpProbeSnapshot snapshot) onSnapshot,
  }) async {
    final enabled = servers.where((s) => s.enabled).toList();
    await Future.wait([
      for (final server in enabled) probeOne(server, onSnapshot: onSnapshot),
    ]);
  }

  Future<void> refreshAll(
    List<McpServer> servers, {
    required void Function(String id, McpProbeSnapshot snapshot) onSnapshot,
  }) => probeEnabled(servers, onSnapshot: onSnapshot);

  Future<void> probeOne(
    McpServer server, {
    required void Function(String id, McpProbeSnapshot snapshot) onSnapshot,
  }) async {
    if (_closed || !server.enabled) return;
    final generation = (_generations[server.id] ?? 0) + 1;
    _generations[server.id] = generation;
    final probeKey = '${server.id}#$generation';
    onSnapshot(
      server.id,
      McpProbeSnapshot(status: McpProbeStatus.checking, generation: generation),
    );
    final held = await _acquireSlot();
    if (!held || _closed || _generations[server.id] != generation) {
      if (held) _releaseSlot();
      return;
    }
    try {
      final result = await _handshake
          .listTools(server, probeKey: probeKey)
          .timeout(timeout);
      if (_closed || _generations[server.id] != generation) return;
      onSnapshot(
        server.id,
        McpProbeSnapshot(
          status: result.status,
          tools: result.tools,
          errorMessage: result.errorMessage,
          generation: generation,
        ),
      );
    } on TimeoutException {
      await _handshake.abort(probeKey);
      if (_closed || _generations[server.id] != generation) return;
      onSnapshot(
        server.id,
        McpProbeSnapshot(
          status: McpProbeStatus.offline,
          generation: generation,
        ),
      );
    } catch (e) {
      appLogger.w('[mcp-probe] ${server.id} failed (${e.runtimeType})');
      await _handshake.abort(probeKey);
      if (_closed || _generations[server.id] != generation) return;
      onSnapshot(
        server.id,
        McpProbeSnapshot(
          status: McpProbeStatus.offline,
          generation: generation,
        ),
      );
    } finally {
      _releaseSlot();
    }
  }

  void cancel(String id) {
    final current = _generations[id] ?? 0;
    unawaited(_handshake.abort('$id#$current'));
    _generations[id] = current + 1;
  }

  Future<void> close() async {
    _closed = true;
    await _handshake.closeAll();
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _waiters.clear();
  }

  Future<bool> _acquireSlot() async {
    while (_active >= maxConcurrent && !_closed) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    if (_closed) return false;
    _active++;
    return true;
  }

  void _releaseSlot() {
    _active = (_active - 1).clamp(0, maxConcurrent);
    if (_waiters.isEmpty) return;
    final next = _waiters.removeAt(0);
    if (!next.isCompleted) next.complete();
  }
}
