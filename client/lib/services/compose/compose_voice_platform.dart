import 'dart:io' show Platform;

/// Whether [ComposeVoiceInput] may call `speech_to_text` on macOS without
/// triggering a TCC abort.
///
/// macOS attributes privacy prompts to the **responsible parent process**. When
/// Flutter is launched from Cursor/VS Code, that parent is the IDE, which lacks
/// `NSSpeechRecognitionUsageDescription`, so `SFSpeechRecognizer.requestAuthorization`
/// aborts instead of showing a dialog (flutter/flutter#70374).
bool get isComposeVoiceMacOsLaunchUsable {
  if (!Platform.isMacOS) return true;
  return !isMacOsIdeSpawnedProcessFromEnv(Platform.environment);
}

/// Detects VS Code / Cursor debug launches from [environment].
bool isMacOsIdeSpawnedProcessFromEnv(Map<String, String> environment) {
  if (environment.containsKey('VSCODE_PID')) return true;
  if (environment.containsKey('VSCODE_INJECTION')) return true;
  if (environment['TERM_PROGRAM'] == 'vscode') return true;
  return false;
}
