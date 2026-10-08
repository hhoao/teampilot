import '../jsonrpc.dart';

/// Streaming `wait_for_message` delivery: response + confirm/abort hooks.
class WaitDelivery {
  const WaitDelivery({
    required this.response,
    required this.confirm,
    required this.abort,
  });

  final JsonRpcResponse response;

  /// Called after the SSE body is written — marks the batch read.
  final Future<void> Function() confirm;

  /// Called when the client disconnects — re-queues the batch.
  final void Function() abort;
}
