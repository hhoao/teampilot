import 'dart:async';
import 'dart:isolate';

import '../../../models/ssh_profile.dart';
import 'ssh_profile_worker.dart';

/// Starts the worker actor inside the spawned profile isolate.
void sshProfileWorkerMain(SshWorkerBootstrap bootstrap) {
  final worker = SshProfileWorker(
    bootstrap: bootstrap,
    send: bootstrap.uiPort.send,
  );
  worker.start();
}

/// One launched worker transport owned by a [SshWorkerLauncher].
class SshWorkerLaunch {
  const SshWorkerLaunch({
    required this.workerIdentity,
    required this.commands,
    required this.messages,
    required this.close,
  });

  final Object workerIdentity;
  final SendPort commands;
  final Stream<Object?> messages;
  final Future<void> Function() close;
}

/// Starts a profile worker and exposes only its serializable message boundary.
abstract interface class SshWorkerLauncher {
  Future<SshWorkerLaunch> spawn({
    required SshProfile profile,
    required int generation,
    required String debugName,
  });
}

/// Production launcher that creates a dedicated named isolate per profile.
class IsolateSshWorkerLauncher implements SshWorkerLauncher {
  const IsolateSshWorkerLauncher({
    this.startupTimeout = const Duration(seconds: 5),
    this.shutdownTimeout = const Duration(seconds: 5),
  });

  final Duration startupTimeout;
  final Duration shutdownTimeout;

  @override
  Future<SshWorkerLaunch> spawn({
    required SshProfile profile,
    required int generation,
    required String debugName,
  }) async {
    final events = ReceivePort();
    final messages = StreamController<Object?>.broadcast();
    final commandPort = Completer<SendPort>();
    final exited = Completer<void>();
    final eventSubscription = events.listen((Object? message) {
      if (message == _workerExitedSignal) {
        if (!exited.isCompleted) exited.complete();
        unawaited(messages.close());
        return;
      }
      final port = _readyCommandPort(message);
      if (port != null && !commandPort.isCompleted) {
        commandPort.complete(port);
        return;
      }
      if (!messages.isClosed) messages.add(message);
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<SshWorkerBootstrap>(
        sshProfileWorkerMain,
        SshWorkerBootstrap(profileId: profile.id, uiPort: events.sendPort),
        debugName: debugName,
      );
      isolate.addOnExitListener(events.sendPort, response: _workerExitedSignal);
      final commands = await commandPort.future.timeout(startupTimeout);
      return SshWorkerLaunch(
        workerIdentity: isolate,
        commands: commands,
        messages: messages.stream,
        close: () => _closeIsolateLaunch(
          isolate: isolate!,
          events: events,
          messages: messages,
          eventSubscription: eventSubscription,
          exited: exited.future,
          shutdownTimeout: shutdownTimeout,
        ),
      );
    } on Object {
      isolate?.kill(priority: Isolate.immediate);
      await eventSubscription.cancel();
      events.close();
      await messages.close();
      rethrow;
    }
  }
}

/// In-process launcher used by tests and the explicit
/// `SSH_WORKER_CAPTURE_MODE=direct` capture mode.
class DirectSshWorkerLauncher implements SshWorkerLauncher {
  @override
  Future<SshWorkerLaunch> spawn({
    required SshProfile profile,
    required int generation,
    required String debugName,
  }) async {
    final events = ReceivePort();
    final messages = StreamController<Object?>.broadcast();
    final commandPort = Completer<SendPort>();
    final subscription = events.listen((Object? message) {
      final port = _readyCommandPort(message);
      if (port != null && !commandPort.isCompleted) {
        commandPort.complete(port);
        return;
      }
      messages.add(message);
    });
    sshProfileWorkerMain(
      SshWorkerBootstrap(profileId: profile.id, uiPort: events.sendPort),
    );
    final commands = await commandPort.future;
    return SshWorkerLaunch(
      workerIdentity: Object(),
      commands: commands,
      messages: messages.stream,
      close: () async {
        await subscription.cancel();
        events.close();
        await messages.close();
      },
    );
  }
}

SendPort? _readyCommandPort(Object? message) {
  if (message is! Map || message['type'] != 'ready') return null;
  final commandPort = message['commandPort'];
  return commandPort is SendPort ? commandPort : null;
}

Future<void> _closeIsolateLaunch({
  required Isolate isolate,
  required ReceivePort events,
  required StreamController<Object?> messages,
  required StreamSubscription<dynamic> eventSubscription,
  required Future<void> exited,
  required Duration shutdownTimeout,
}) async {
  try {
    await exited.timeout(shutdownTimeout);
  } on TimeoutException {
    isolate.kill(priority: Isolate.immediate);
  } finally {
    await eventSubscription.cancel();
    events.close();
    await messages.close();
  }
}

const _workerExitedSignal = '__teampilot_ssh_worker_exited__';
