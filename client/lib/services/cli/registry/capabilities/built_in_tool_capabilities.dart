import 'executable_resolver_capability.dart';
import 'presence_capability.dart';
import 'transcript_probe_capability.dart';

final class FlashskyaiTranscriptProbe implements TranscriptProbeCapability {
  const FlashskyaiTranscriptProbe();
  @override
  bool get probeHistoryFiles => false;
}

final class ClaudeTranscriptProbe implements TranscriptProbeCapability {
  const ClaudeTranscriptProbe();
  @override
  bool get probeHistoryFiles => true;
}

final class CodexTranscriptProbe implements TranscriptProbeCapability {
  const CodexTranscriptProbe();
  @override
  bool get probeHistoryFiles => false;
}

final class FlashskyaiExecutableResolver implements ExecutableResolverCapability {
  const FlashskyaiExecutableResolver();
  @override
  String get defaultExecutableName => 'flashskyai';
  @override
  String get preferencesPathKey => 'flashskyai';
}

final class ClaudeExecutableResolver implements ExecutableResolverCapability {
  const ClaudeExecutableResolver();
  @override
  String get defaultExecutableName => 'claude';
  @override
  String get preferencesPathKey => 'claude';
}

final class CodexExecutableResolver implements ExecutableResolverCapability {
  const CodexExecutableResolver();
  @override
  String get defaultExecutableName => 'codex';
  @override
  String get preferencesPathKey => 'codex';
}

final class FlashskyaiPresence implements PresenceCapability {
  const FlashskyaiPresence();
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => true;
}

final class ClaudePresence implements PresenceCapability {
  const ClaudePresence();
  @override
  bool get usesClaudeRoster => true;
  @override
  bool get usesShellActivity => false;
}

final class CodexPresence implements PresenceCapability {
  const CodexPresence();
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => false;
}

final class OpencodeTranscriptProbe implements TranscriptProbeCapability {
  const OpencodeTranscriptProbe();
  @override
  bool get probeHistoryFiles => false;
}

final class OpencodeExecutableResolver implements ExecutableResolverCapability {
  const OpencodeExecutableResolver();
  @override
  String get defaultExecutableName => 'opencode';
  @override
  String get preferencesPathKey => 'opencode';
}

final class OpencodePresence implements PresenceCapability {
  const OpencodePresence();
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => false;
}
