# teammate_bus_bridge

Standalone stdio↔HTTP bridge so `claude` (and other stdio-MCP CLIs) can block
indefinitely on `wait_for_message`. Claude's HTTP MCP transport hard-caps a
single request at ~6 minutes (fetch/undici layer, not reset by progress, not
configurable); stdio has no such cap. This dumb-pipe child process is spawned
by the CLI over stdio and proxies each JSON-RPC message to the app's existing
loopback bus using `dart:io` HttpClient, which has no response-body timeout.

## Build
    dart compile exe bin/teammate_bus_bridge.dart -o teammate_bus_bridge

## Run
    teammate_bus_bridge --member <id> --bus-url http://127.0.0.1:<port>/mcp
