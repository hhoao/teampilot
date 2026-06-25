import 'dart:async';
import 'dart:io';

import 'package:mock_anthropic/scenarios/ping_pong_mixed_claude.dart';
import 'package:mock_anthropic/server.dart';

Future<void> main() async {
  final server = MockAnthropicServer(
    scenarios: pingPongMixedClaudeScenarios(),
  );
  await server.start();
  final port = server.port;

  stdout.writeln('Mock Anthropic API listening at http://127.0.0.1:$port');
  stdout.writeln('Messages: http://127.0.0.1:$port/v1/messages');
  stdout.writeln('Lead API key: lead-script');
  stdout.writeln('Worker API key: worker-script');
  stdout.writeln('Press Ctrl+C to stop.');

  final done = Completer<void>();
  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    if (!done.isCompleted) {
      done.complete();
    }
  });
  await done.future;
}
