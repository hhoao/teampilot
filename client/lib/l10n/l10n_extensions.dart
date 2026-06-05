// Hand-maintained extensions for generated [AppLocalizations].
// Edit app_en.arb / app_zh.arb, then flutter pub get or flutter run (generate: true).

import 'package:flutter/widgets.dart';

import '../models/team_config.dart';
import '../services/editor/editor_messages.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

extension AppLocalizationsX on AppLocalizations {
  /// Display name for a [LayoutPreferences.themeColorPreset] id.
  String themeColorPresetName(String id) {
    switch (id) {
      case 'ocean':
        return themePresetOcean;
      case 'violet':
        return themePresetViolet;
      case 'amber':
        return themePresetAmber;
      case 'forest':
        return themePresetForest;
      case 'graphite':
      default:
        return themePresetGraphite;
    }
  }

  String providerListCaption(int modelCount, bool proxyEnabled) {
    final countPart = providerListModelCount(modelCount);
    final proxyPart = proxyEnabled ? proxyOnShort : proxyOffShort;
    return '$countPart · $proxyPart';
  }

  String appProviderToolLabel(CliTool cli) {
    return switch (cli) {
      CliTool.claude => appProviderToolClaude,
      CliTool.codex => appProviderToolCodex,
      CliTool.flashskyai => appProviderToolFlashskyai,
      CliTool.opencode => appProviderToolOpencode,
    };
  }

  String appProviderClaudeApiFormatOption(String value) {
    return switch (value) {
      'anthropic' => appProviderClaudeApiFormatAnthropic,
      'openai_chat' => appProviderClaudeApiFormatOpenaiChat,
      'openai_responses' => appProviderClaudeApiFormatOpenaiResponses,
      'gemini_native' => appProviderClaudeApiFormatGeminiNative,
      _ => value,
    };
  }

  String appProviderClaudeAuthFieldOption(String value) {
    return switch (value) {
      'ANTHROPIC_AUTH_TOKEN' => appProviderClaudeAuthTokenDefault,
      'ANTHROPIC_API_KEY' => appProviderClaudeAuthApiKey,
      _ => value,
    };
  }
}

extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension EditorL10n on AppLocalizations {
  String editorSnackbarMessage(String code) {
    if (code.startsWith(EditorMessage.saveFailedPrefix)) {
      final detail = code.substring(EditorMessage.saveFailedPrefix.length);
      return editorSaveFailed(detail);
    }
    return switch (code) {
      EditorMessage.binaryFile => editorBinaryFileHint,
      EditorMessage.readOnly => editorFileReadOnly,
      EditorMessage.fileNotFound => editorFileNotFound,
      EditorMessage.fileTooLarge => editorFileTooLarge,
      EditorMessage.couldNotRead => editorCouldNotReadFile,
      _ => code,
    };
  }

  String editorPanelErrorMessage(String code) => editorSnackbarMessage(code);
}
