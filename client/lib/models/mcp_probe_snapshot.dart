import 'package:flutter/foundation.dart';

enum McpProbeStatus { checking, online, offline, needsAuth }

@immutable
class McpProbeTool {
  const McpProbeTool({required this.name, this.description = ''});

  final String name;
  final String description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpProbeTool &&
          name == other.name &&
          description == other.description;

  @override
  int get hashCode => Object.hash(name, description);
}

@immutable
class McpProbeSnapshot {
  const McpProbeSnapshot({
    required this.status,
    this.tools = const [],
    this.errorMessage,
    this.generation = 0,
  });

  final McpProbeStatus status;
  final List<McpProbeTool> tools;
  final String? errorMessage;
  final int generation;

  McpProbeSnapshot copyWith({
    McpProbeStatus? status,
    List<McpProbeTool>? tools,
    String? errorMessage,
    int? generation,
    bool clearError = false,
  }) => McpProbeSnapshot(
    status: status ?? this.status,
    tools: tools ?? this.tools,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    generation: generation ?? this.generation,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpProbeSnapshot &&
          status == other.status &&
          listEquals(tools, other.tools) &&
          errorMessage == other.errorMessage &&
          generation == other.generation;

  @override
  int get hashCode =>
      Object.hash(status, Object.hashAll(tools), errorMessage, generation);
}

@immutable
class McpHandshakeResult {
  const McpHandshakeResult.ok(this.tools)
    : status = McpProbeStatus.online,
      errorMessage = null;

  const McpHandshakeResult.fail({
    required this.status,
    this.errorMessage,
  }) : tools = const [];

  final McpProbeStatus status;
  final List<McpProbeTool> tools;
  final String? errorMessage;
}
