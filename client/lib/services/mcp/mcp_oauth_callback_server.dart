import 'dart:async';
import 'dart:io';

import 'mcp_oauth_discovery.dart';

/// Local OAuth redirect listener (`http://localhost:{port}/callback`).
class McpOAuthCallbackServer {
  McpOAuthCallbackServer({
    this.port = 3118,
    this.timeout = const Duration(minutes: 5),
  });

  final int port;
  final Duration timeout;

  HttpServer? _server;
  Timer? _timer;
  Completer<Uri>? _completer;

  Future<Uri> listen({
    required String expectedState,
    void Function(Uri redirectUri)? onListening,
  }) async {
    final completer = Completer<Uri>();
    _completer = completer;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    onListening?.call(Uri.parse('http://localhost:$port/callback'));

    _timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Authentication timed out'),
        );
      }
      unawaited(close());
    });

    _server!.listen((request) async {
      if (request.uri.path != '/callback') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }

      final params = request.uri.queryParameters;
      final error = params['error'];
      if (error != null) {
        final description = params['error_description'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<h1>Authentication Error</h1><p>$error $description</p>',
        );
        await request.response.close();
        if (!completer.isCompleted) {
          completer.completeError(
            McpOAuthCallbackException('OAuth error: $error $description'),
          );
        }
        unawaited(close());
        return;
      }

      final state = params['state'];
      final code = params['code'];
      if (state != expectedState) {
        request.response.statusCode = 400;
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<h1>Authentication Error</h1><p>Invalid state parameter.</p>',
        );
        await request.response.close();
        if (!completer.isCompleted) {
          completer.completeError(
            McpOAuthCallbackException('OAuth state mismatch'),
          );
        }
        unawaited(close());
        return;
      }

      if (code == null || code.isEmpty) {
        request.response.statusCode = 400;
        await request.response.close();
        return;
      }

      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<h1>Authentication Successful</h1>'
        '<p>You can close this window and return to TeamPilot.</p>',
      );
      await request.response.close();

      if (!completer.isCompleted) {
        completer.complete(request.uri);
      }
      unawaited(close());
    });

    return completer.future;
  }

  Future<void> close({bool cancelled = false}) async {
    _timer?.cancel();
    _timer = null;
    final completer = _completer;
    _completer = null;
    if (cancelled && completer != null && !completer.isCompleted) {
      completer.completeError(const McpOAuthCancelledException());
    }
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }
}

class McpOAuthCallbackException implements Exception {
  McpOAuthCallbackException(this.message);
  final String message;
  @override
  String toString() => message;
}
