import '../../artifacts/artifact_exceptions.dart';
import '../../artifacts/artifact_handle.dart';
import '../jsonrpc.dart';
import '../toolkit/mcp_schema.dart';
import '../toolkit/teammate_bus_tool.dart';
import '../toolkit/teammate_bus_tool_call.dart';
import '../toolkit/teammate_bus_tool_context.dart';
import '../toolkit/teammate_bus_tool_name.dart';

final class PublishArtifactTool extends TeammateBusTool {
  const PublishArtifactTool();

  static const pathKey = 'path';
  static const nameKey = 'name';
  static const kindKey = 'kind';
  static const overwriteKey = 'overwrite';

  @override
  TeammateBusToolName get name => TeammateBusToolName.publishArtifact;

  @override
  bool isEnabled(TeammateBusToolContext ctx) => ctx.artifacts != null;

  @override
  String get description =>
      'Publish a file on YOUR machine so a teammate can fetch it (members '
      'do not share a filesystem). Records only a handle (name + path + '
      'size); the file is not copied until someone fetches it. path is an '
      'absolute path on your own machine; name is the logical name '
      'teammates fetch by. Single files only. Fails if name is already '
      'published unless overwrite=true.';

  @override
  Map<String, Object?> get inputSchema => McpSchema.object(
    properties: {
      pathKey: McpSchema.string,
      nameKey: McpSchema.string,
      kindKey: McpSchema.stringEnum(['file']),
      overwriteKey: McpSchema.boolean,
    },
    required: [pathKey, nameKey],
  );

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async {
    final unavailable = call.artifactsUnavailable();
    if (unavailable != null) return unavailable;

    final path = call.argString(PublishArtifactTool.pathKey)?.trim() ?? '';
    final name = call.argString(PublishArtifactTool.nameKey)?.trim() ?? '';
    if (path.isEmpty || name.isEmpty) {
      return call.toolError(
        'publish_artifact requires a non-empty "path" and "name".',
      );
    }
    final kind = ArtifactKind.tryParse(
      call.argString(PublishArtifactTool.kindKey),
    );
    if (kind == null) {
      return call.toolError(
        'Only kind=file is supported (directory/tar transfer is not yet '
        'available).',
      );
    }
    final overwrite = call.argBool(
      PublishArtifactTool.overwriteKey,
      defaultValue: false,
    );
    try {
      final handle = await call.artifacts.publish(
        publisherMemberId: call.memberId,
        path: path,
        name: name,
        kind: kind,
        overwrite: overwrite,
      );
      return call.ok(
        'Published "${handle.name}" (${handle.sizeBytes} bytes). Teammates can '
        'fetch_artifact(name: "${handle.name}", destPath: ...).',
      );
    } on ArtifactException catch (error) {
      return call.toolError(error.toString());
    }
  }
}
