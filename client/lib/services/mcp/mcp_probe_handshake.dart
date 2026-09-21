import '../../models/mcp_probe_snapshot.dart';
import '../../models/mcp_server.dart';

abstract class McpProbeHandshake {
  Future<McpHandshakeResult> listTools(
    McpServer server, {
    required String probeKey,
  });

  Future<void> abort(String probeKey);

  Future<void> closeAll();
}

const kMcpProbeMaxListPages = 20;

Future<List<McpProbeTool>> collectListedTools({
  required Future<({List<McpProbeTool> tools, String? nextCursor})> Function(
    String? cursor,
  )
  listPage,
  int maxPages = kMcpProbeMaxListPages,
}) async {
  final out = <McpProbeTool>[];
  String? cursor;
  for (var page = 0; page < maxPages; page++) {
    final result = await listPage(cursor);
    out.addAll(result.tools);
    final next = result.nextCursor?.trim();
    if (next == null || next.isEmpty) return out;
    cursor = next;
  }
  return out;
}
