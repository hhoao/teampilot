import 'dart:async';
import 'dart:io';

import 'package:mock_model_gateway/core/turns.dart';
import 'package:mock_model_gateway/server.dart';

Future<void> main() async {
  final server = MockModelGatewayServer.scenarios({
    'simple-script': MockScenario(
      turns: [
        TextTurn('MARK_A1'),
        TextTurn('MARK_A2'),
        TextTurn('MARK_A3'),
      ],
    ),
    'lead-script': MockScenario(
      turns: [
        TextTurn('lead-ready'),
      ],
    ),
    'worker-script': MockScenario(
      turns: [
        TextTurn('worker-ready'),
      ],
    ),
  });
  await server.start();
  final port = server.port;

  stdout.writeln('Mock Model Gateway listening at http://127.0.0.1:$port');
  stdout.writeln('  Anthropic:  http://127.0.0.1:$port/v1/messages');
  stdout.writeln('  Chat:       http://127.0.0.1:$port/v1/chat/completions');
  stdout.writeln('  Responses:  http://127.0.0.1:$port/v1/responses');
  stdout.writeln('API keys: simple-script | lead-script | worker-script');
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
