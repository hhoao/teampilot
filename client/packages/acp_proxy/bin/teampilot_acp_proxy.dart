import 'dart:async';
import 'dart:io';

import 'package:acp_proxy/acp_proxy.dart';

/// `--detach` spawns this script again without the flag and exits 0.
/// Otherwise one loopback port per `--cli` stays up, and idle sessions are
/// reaped once a minute.
Future<void> main(List<String> args) async {
  final parsed = parseAcpProxyArgs(args);
  if (parsed.detach) {
    await Process.start(
      Platform.resolvedExecutable,
      acpProxyDetachArguments(
        executableArguments: Platform.executableArguments,
        scriptPath: Platform.script.toFilePath(),
        executable: Platform.resolvedExecutable,
        args: args,
      ),
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  final spool = AcpProxySpool(root: parsed.root);
  final agents = <AcpProxyAgent>[];
  final listener = AcpProxyListener(
    root: parsed.root,
    cliIds: parsed.cliIds,
    pid: pid,
    agentForCli: (cliId) {
      final agent = AcpProxyAgent(
        endpointCli: cliId,
        book: AcpProxySessionBook(),
        spool: spool,
        upstreams: <String, AcpUpstream>{},
      );
      agents.add(agent);
      return agent;
    },
  );
  await listener.start();
  _RunningProxy(listener, agents, parsed.idleTimeout).schedule();
  await Completer<void>().future;
}

/// Owns the listener for the process lifetime and runs the idle tick.
class _RunningProxy {
  _RunningProxy(this.listener, this.agents, this.idleTimeout);

  final AcpProxyListener listener;
  final List<AcpProxyAgent> agents;
  final Duration idleTimeout;
  var _reaping = false;

  void schedule() {
    Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(onTick());
    });
  }

  Future<void> onTick() async {
    if (_reaping) return;
    // No ports and no agents: nothing to reap. Reading [listener] also keeps
    // the accept loop referenced by this timer.
    if (listener.cliIds.isEmpty && agents.isEmpty) return;
    _reaping = true;
    try {
      final now = DateTime.now();
      for (final agent in agents) {
        await agent.reapIdle(now: now, idleTimeout: idleTimeout);
      }
    } catch (error) {
      stderr.writeln('acp-proxy: idle reap failed: $error');
    } finally {
      _reaping = false;
    }
  }
}
