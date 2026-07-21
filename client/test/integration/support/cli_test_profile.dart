import 'dart:io';

import 'package:mock_model_gateway/scenarios/mixed_collab_3plus.dart';
import 'package:mock_model_gateway/scenarios/simple_3turn.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/bus_transport_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import 'cli_test_profile_claude_boot.dart';
import 'cli_test_profile_codex_boot.dart';
import 'cli_test_profile_flashskyai_boot.dart';
import 'cli_test_profile_opencode_boot.dart';

/// Wire protocol the mock gateway should speak for a CLI matrix cell.
enum CliTestWire {
  anthropic,
  openaiChat,
  openaiResponses,

  /// Placeholder until Task 15 discovers the cursor redirect surface.
  cursor,
}

/// How the CLI consumes TeamBus (mirrors [BusTransportCapability]).
enum CliTestBusStyle {
  /// Parks in long-blocking `wait_for_message` (claude/codex/opencode/…).
  longWait,

  /// Idle-at-prompt + stdin doorbell + short MCP (`read_messages`).
  doorbell,
}

/// Opaque PTY/session handle for boot hooks until the L2 harness lands.
typedef CliTestSessionHandle = Object;

/// Maps logical recipe `toolRef` → on-wire tool name for one CLI.
typedef CliTestToolNameMapper = String Function(String toolRef);

/// Per-CLI knobs for mock-gateway matrix L2 cells (Task 7).
///
/// Does **not** own the harness (Task 8). Boot / fullscreen hooks are stubs
/// until L2 cells wire real PTY automation.
final class CliTestProfile {
  CliTestProfile({
    required this.tool,
    required this.wire,
    required this.toolName,
    required this.assistantVisibleMarkers,
    required this.binaryName,
    required this.resolveBinary,
    required this.bootToPrompt,
    required this.dismissBootGates,
    this.providerType,
    this.fullscreenDeliverNotes = '',
    this.gatewayRedirectNotes = '',
    this.collabLeadMarkers = const [markLead1, markLead2, markLeadDone],
    this.collabWorkerMarkers = const [markWorker1],
  });

  final CliTool tool;
  final CliTestWire wire;

  /// Optional provider catalog `provider_type` pin (flashskyai → `openai`).
  final String? providerType;

  /// PATH / prefs executable basename (e.g. `claude`, `cursor-agent`).
  final String binaryName;

  /// Resolves [binaryName] on PATH; `null` when missing (L2 skip reason).
  final String? Function() resolveBinary;

  /// Logical `teambus.*` / `native.*` → CLI on-wire tool name.
  final CliTestToolNameMapper toolName;

  /// Simple-recipe PTY / bubble markers ([markA1]/[markA2]/[markA3]).
  final List<String> assistantVisibleMarkers;

  /// Lead-seat markers for mixed/native collab recipes.
  final List<String> collabLeadMarkers;

  /// Worker-seat markers for mixed/native collab recipes.
  final List<String> collabWorkerMarkers;

  /// Wait until the CLI composer/prompt is ready (stub until L2).
  final Future<bool> Function(CliTestSessionHandle session) bootToPrompt;

  /// Dismiss trust / API-key / update modals (stub until L2).
  final Future<void> Function(CliTestSessionHandle session) dismissBootGates;

  /// Notes for fullscreen paste / CR ACK (harness may specialize later).
  final String fullscreenDeliverNotes;

  /// How to point the CLI at the loopback gateway (baseUrl / fake creds).
  final String gatewayRedirectNotes;

  /// Derived from production [CliToolRegistry.supportsNativeTeam] — not a
  /// hand-maintained duplicate.
  bool get supportsNativeTeam =>
      CliToolRegistry.builtIn().supportsNativeTeam(tool);

  /// Derived from [BusTransportCapability.longBlockingWaitForMessage].
  CliTestBusStyle get busStyle {
    final bus =
        CliToolRegistry.builtIn().capability<BusTransportCapability>(tool);
    if (bus != null && !bus.longBlockingWaitForMessage) {
      return CliTestBusStyle.doorbell;
    }
    return CliTestBusStyle.longWait;
  }

  /// Cheap gateway wiring hints for provider config / env injection.
  Map<String, String> gatewayCredentialHints(String gatewayBaseUrl) {
    final base = gatewayBaseUrl.replaceAll(RegExp(r'/+$'), '');
    // OpenAI-compatible CLIs (flashskyai/opencode) treat base_url as the
    // `/v1` root and append `/chat/completions`. Anthropic uses the host root
    // and appends `/v1/messages` itself.
    final effectiveBase = switch (wire) {
      CliTestWire.openaiChat || CliTestWire.openaiResponses =>
        base.endsWith('/v1') ? base : '$base/v1',
      CliTestWire.anthropic || CliTestWire.cursor => base,
    };
    final hints = <String, String>{
      'baseUrl': effectiveBase,
      'apiKey': 'test-key',
    };
    if (providerType != null) {
      hints['provider_type'] = providerType!;
    }
    return hints;
  }

  /// Default thread matchers: substring containment (harness may override).
  bool matchesUserBubble(String haystack, String expectedUserText) =>
      haystack.contains(expectedUserText);

  bool matchesAssistantMarker(String haystack, String marker) =>
      haystack.contains(marker);
}

/// Factory for the five launch-supported CLIs.
abstract final class CliTestProfiles {
  CliTestProfiles._();

  static CliTestProfile forTool(CliTool tool) {
    return switch (tool) {
      CliTool.claude => _claude,
      CliTool.flashskyai => _flashskyai,
      CliTool.codex => _codex,
      CliTool.opencode => _opencode,
      CliTool.cursor => _cursor,
    };
  }

  static final CliTestProfile _claude = CliTestProfile(
    tool: CliTool.claude,
    wire: CliTestWire.anthropic,
    binaryName: 'claude',
    resolveBinary: () => whichOnPath('claude'),
    toolName: mapMcpPrefixedToolRef,
    assistantVisibleMarkers: const [markA1, markA2, markA3],
    bootToPrompt: (session) async {
      if (session is! TerminalSession) return false;
      return bootClaudeToPrompt(session);
    },
    dismissBootGates: (session) async {
      if (session is! TerminalSession) return;
      await dismissClaudeBootGates(session);
    },
    fullscreenDeliverNotes:
        'Fullscreen paste + grid ACK (ClaudeTerminalBehavior).',
    gatewayRedirectNotes:
        'Point Anthropic-compatible base URL at gateway /v1/messages; '
        'inject fake API key via provider credentials.',
  );

  static final CliTestProfile _flashskyai = CliTestProfile(
    tool: CliTool.flashskyai,
    wire: CliTestWire.openaiChat,
    providerType: 'openai',
    binaryName: 'flashskyai',
    resolveBinary: () => whichOnPath('flashskyai'),
    // Claude-shaped mcpServers → same mcp__teammate-bus__* wire names until
    // an L2 probe proves otherwise.
    toolName: mapMcpPrefixedToolRef,
    assistantVisibleMarkers: const [markA1, markA2, markA3],
    bootToPrompt: (session) async {
      if (session is! TerminalSession) return false;
      return bootFlashskyaiToPrompt(session);
    },
    dismissBootGates: (session) async {
      if (session is! TerminalSession) return;
      await dismissFlashskyaiBootGates(session);
    },
    fullscreenDeliverNotes:
        'Fullscreen paste + grid ACK (FlashskyaiTerminalBehavior; Ink ❯).',
    gatewayRedirectNotes:
        'Pin provider_type=openai; OpenAI Chat Completions at gateway '
        '/v1/chat/completions.',
  );

  static final CliTestProfile _codex = CliTestProfile(
    tool: CliTool.codex,
    wire: CliTestWire.openaiResponses,
    binaryName: 'codex',
    resolveBinary: () => whichOnPath('codex'),
    // Codex Responses exposes MCP as namespace tools; wire names use
    // `mcp__<server>::<tool>` so the Responses SSE encoder can emit
    // `namespace` + short `name` (hyphens in server ids → underscores).
    toolName: mapCodexNamespacedMcpToolRef,
    assistantVisibleMarkers: const [markA1, markA2, markA3],
    bootToPrompt: (session) async {
      if (session is! TerminalSession) return false;
      return bootCodexToPrompt(session);
    },
    dismissBootGates: (session) async {
      if (session is! TerminalSession) return;
      await dismissCodexBootGates(session);
    },
    fullscreenDeliverNotes:
        'Fullscreen paste; composerMovesDown CR ACK (CodexTerminalBehavior).',
    gatewayRedirectNotes:
        'Codex wire_api=responses → gateway /v1/responses; fake OpenAI creds.',
  );

  static final CliTestProfile _opencode = CliTestProfile(
    tool: CliTool.opencode,
    wire: CliTestWire.openaiChat,
    binaryName: 'opencode',
    resolveBinary: () => whichOnPath('opencode'),
    // OpenCode registers MCP as `<server>_<tool>` (hyphens kept; see
    // anomalyco/opencode mcp/index.ts convertMcpTool keying).
    toolName: mapOpencodeMcpToolRef,
    assistantVisibleMarkers: const [markA1, markA2, markA3],
    bootToPrompt: (session) async {
      if (session is! TerminalSession) return false;
      return bootOpencodeToPrompt(session);
    },
    dismissBootGates: (session) async {
      if (session is! TerminalSession) return;
      await dismissOpencodeBootGates(session);
    },
    fullscreenDeliverNotes:
        'Fullscreen paste; anchorCellClears CR ACK (OpencodeTerminalBehavior).',
    gatewayRedirectNotes:
        'Custom provider npm=@ai-sdk/openai-compatible; OpenAI Chat '
        'Completions at gateway /v1/chat/completions (stream: true SSE).',
  );

  static final CliTestProfile _cursor = CliTestProfile(
    tool: CliTool.cursor,
    wire: CliTestWire.cursor,
    binaryName: 'cursor-agent',
    resolveBinary: () => whichOnPath('cursor-agent'),
    // Doorbell / short MCP: bare tool ids (no mcp__ prefix) until Task 15
    // discovery confirms Cursor's on-wire names.
    toolName: mapShortMcpToolRef,
    assistantVisibleMarkers: const [markA1, markA2, markA3],
    bootToPrompt: bootToPromptStub,
    dismissBootGates: dismissBootGatesStub,
    fullscreenDeliverNotes:
        'Fullscreen paste + grid ACK; doorbell via stdin inject + read_messages.',
    gatewayRedirectNotes:
        'TODO(Task 15): spike cursor-agent custom base URL / auth so traffic '
        'hits loopback only — never Cursor cloud.',
  );
}

/// Claude / flashskyai (and best-effort peers): `teambus.X` →
/// `mcp__teammate-bus__X`; `native.TeamCreate` → `TeamCreate`.
String mapMcpPrefixedToolRef(String toolRef) {
  const teambus = 'teambus.';
  if (toolRef.startsWith(teambus)) {
    return 'mcp__${teammateBusMcpServerName}__'
        '${toolRef.substring(teambus.length)}';
  }
  const native = 'native.';
  if (toolRef.startsWith(native)) {
    return toolRef.substring(native.length);
  }
  return toolRef;
}

/// Codex Responses namespace tools: `teambus.X` → `mcp__teammate_bus::X`.
///
/// Codex sanitizes MCP server ids (`teammate-bus` → `teammate_bus`) and exposes
/// tools under `type: "namespace"`. The Responses encoder splits on `::` into
/// `namespace` + short `name` so Codex can dispatch `tools/call`.
String mapCodexNamespacedMcpToolRef(String toolRef) {
  const teambus = 'teambus.';
  if (toolRef.startsWith(teambus)) {
    final server = teammateBusMcpServerName.replaceAll('-', '_');
    return 'mcp__$server::${toolRef.substring(teambus.length)}';
  }
  const native = 'native.';
  if (toolRef.startsWith(native)) {
    return toolRef.substring(native.length);
  }
  return toolRef;
}

/// OpenCode Chat Completions tools: `teambus.X` → `teammate-bus_X`.
///
/// OpenCode keys MCP tools as `<sanitizedServer>_<sanitizedTool>` (keeps
/// hyphens; replaces other non `[A-Za-z0-9_-]` with `_`).
String mapOpencodeMcpToolRef(String toolRef) {
  const teambus = 'teambus.';
  if (toolRef.startsWith(teambus)) {
    return '${teammateBusMcpServerName}_${toolRef.substring(teambus.length)}';
  }
  const native = 'native.';
  if (toolRef.startsWith(native)) {
    return toolRef.substring(native.length);
  }
  return toolRef;
}

/// Cursor best-effort: short MCP names (`send_message`, not `mcp__…`).
String mapShortMcpToolRef(String toolRef) {
  const teambus = 'teambus.';
  if (toolRef.startsWith(teambus)) {
    return toolRef.substring(teambus.length);
  }
  const native = 'native.';
  if (toolRef.startsWith(native)) {
    return toolRef.substring(native.length);
  }
  return toolRef;
}

/// Resolves [binary] via `which`; `null` when missing or `which` fails.
String? whichOnPath(String binary) {
  try {
    final result = Process.runSync('which', [binary]);
    if (result.exitCode != 0) return null;
    final line = result.stdout.toString().trim().split('\n').first.trim();
    return line.isEmpty ? null : line;
  } on ProcessException {
    return null;
  }
}

Future<bool> bootToPromptStub(CliTestSessionHandle session) async {
  // TODO(L2 / Task 8+): wait for CLI prompt after [dismissBootGates].
  return false;
}

Future<void> dismissBootGatesStub(CliTestSessionHandle session) async {
  // TODO(L2 / Task 8+): dismiss trust / API-key / update modals.
}
