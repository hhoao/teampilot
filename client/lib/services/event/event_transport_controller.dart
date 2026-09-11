import '../../utils/logging/logger.dart';
import 'event_transport_client.dart';

/// Home-role for the process-lifetime event transport.
enum EventTransportRole { server, client, none }

/// Start/stop handle so tests can fake Server/Client without binding ports.
abstract interface class EventTransportEndpoint {
  Future<void> start();
  Future<void> stop();
}

/// Adapts existing Server/Client `start`/`stop` tear-offs.
final class CallbackEventTransportEndpoint implements EventTransportEndpoint {
  CallbackEventTransportEndpoint({
    required Future<void> Function() start,
    required Future<void> Function() stop,
  }) : _start = start,
       _stop = stop;

  final Future<void> Function() _start;
  final Future<void> Function() _stop;

  @override
  Future<void> start() => _start();

  @override
  Future<void> stop() => _stop();
}

/// Process-lifetime role switch: local home runs Server, ssh home runs Client.
///
/// Does not import dartssh2. The ssh `open:` closure is supplied by the
/// wiring layer when applying [EventTransportRole.client].
final class EventTransportController {
  EventTransportController({
    required EventTransportEndpoint Function() createServer,
    required EventTransportEndpoint Function({
      required Future<EventTransportByteChannel> Function() open,
    })
    createClient,
  }) : _createServer = createServer,
       _createClient = createClient;

  final EventTransportEndpoint Function() _createServer;
  final EventTransportEndpoint Function({
    required Future<EventTransportByteChannel> Function() open,
  })
  _createClient;

  EventTransportRole _role = EventTransportRole.none;
  EventTransportEndpoint? _server;
  EventTransportEndpoint? _client;

  EventTransportRole get role => _role;

  /// Idempotent: applying the current role is a no-op. Switching roles always
  /// stops the outgoing endpoint before starting the incoming one.
  Future<void> apply(
    EventTransportRole role, {
    Future<EventTransportByteChannel> Function()? open,
  }) async {
    if (role == _role) return;
    try {
      await _stopServer();
      await _stopClient();
      switch (role) {
        case EventTransportRole.server:
          final server = _createServer();
          _server = server;
          await server.start();
        case EventTransportRole.client:
          final opener = open;
          if (opener == null) {
            appLogger.w('[event-transport] client role requires open');
            _role = EventTransportRole.none;
            return;
          }
          final client = _createClient(open: opener);
          _client = client;
          await client.start();
        case EventTransportRole.none:
          break;
      }
      _role = role;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[event-transport] apply $role failed',
        error: error,
        stackTrace: stackTrace,
      );
      await _stopServer();
      await _stopClient();
      _role = EventTransportRole.none;
    }
  }

  Future<void> _stopServer() async {
    final server = _server;
    _server = null;
    if (server == null) return;
    try {
      await server.stop();
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[event-transport] stop server failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _stopClient() async {
    final client = _client;
    _client = null;
    if (client == null) return;
    try {
      await client.stop();
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[event-transport] stop client failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
