import 'dart:async';
import 'dart:io';

import 'package:teampilot_connect_relay/relay_server.dart';

Future<void> main(List<String> arguments) async {
  final bind = _argOf(arguments, 'bind') ?? '0.0.0.0';
  final port = int.tryParse(_argOf(arguments, 'port') ?? '') ?? 2769;

  final relay = RelayServer();
  await relay.start(address: bind, port: port);
  stdout.writeln('teampilot_connect_relay listening on $bind:${relay.port}');

  final done = Completer<void>();
  ProcessSignal.sigint.watch().listen((_) => done.complete());
  ProcessSignal.sigterm.watch().listen((_) => done.complete());
  await done.future;
  await relay.stop();
}

String? _argOf(List<String> arguments, String name) {
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--$name' && i + 1 < arguments.length) {
      return arguments[i + 1];
    }
    final prefix = '--$name=';
    if (argument.startsWith(prefix)) {
      return argument.substring(prefix.length);
    }
  }
  return null;
}
