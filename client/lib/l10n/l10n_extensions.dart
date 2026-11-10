// Hand-maintained extensions for slang-generated [AppLocalizations].
// Edit app_en.arb / app_zh.arb, then run `dart run slang` (see slang.yaml).

import 'package:flutter/widgets.dart';

import '../models/managed_provider.dart';
import '../models/team_config.dart';
import '../services/provider_usage/managed_provider_presets.dart';
import '../services/editor/editor_messages.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

extension AppLocalizationsX on AppLocalizations {
  /// Display name for a [LayoutPreferences.themeColorPreset] id.
  String themeColorPresetName(String id) {
    switch (id) {
      case 'ocean':
        return theme.presetOcean;
      case 'violet':
        return theme.presetViolet;
      case 'amber':
        return theme.presetAmber;
      case 'forest':
        return theme.presetForest;
      case 'graphite':
      default:
        return theme.presetGraphite;
    }
  }

  String providerListCaption(int modelCount, bool proxyEnabled) {
    final countPart = provider.listModelCount(count: modelCount);
    final proxyPart = proxyEnabled ? proxyOnShort : proxyOffShort;
    return '$countPart · $proxyPart';
  }

  String appProviderToolLabel(CliTool cli) {
    return switch (cli) {
      CliTool.claude => appProvider.toolClaude,
      CliTool.codex => appProvider.toolCodex,
      CliTool.flashskyai => appProvider.toolFlashskyai,
      CliTool.opencode => appProvider.toolOpencode,
      CliTool.cursor => appProvider.toolCursor,
      CliTool.gemini => appProvider.toolGemini,
      CliTool.codebuddy => appProvider.toolCodebuddy,
      CliTool.antigravity => appProvider.toolAntigravity,
      CliTool.qoder => appProvider.toolQoder,
      CliTool.qoderCn => appProvider.toolQoderCn,
    };
  }

  String appProviderClaudeAuthFieldOption(String value) {
    return switch (value) {
      'ANTHROPIC_AUTH_TOKEN' => appProvider.claudeAuthTokenDefault,
      'ANTHROPIC_API_KEY' => appProvider.claudeAuthApiKey,
      _ => value,
    };
  }

  String managedProviderPresetLabel(String id) => switch (id) {
    'codex' => managedProviders.quickPresetCodex,
    'claude-code' => managedProviders.quickPresetClaudeCode,
    'cursor' => managedProviders.quickPresetCursor,
    'codebuddy' => managedProviders.quickPresetCodebuddy,
    'deepseek' => managedProviders.quickPresetDeepSeek,
    'opencode-go' => managedProviders.quickPresetOpencodeGo,
    'qoder' => managedProviders.quickPresetQoder,
    'qoder-cn' => managedProviders.quickPresetQoderCn,
    kManagedProviderQuickPresetCustomId => managedProviders.quickPresetCustom,
    _ => id,
  };

  String managedProviderPresetHint(String id) => switch (id) {
    'codex' => managedProviders.quickPresetCodexHint,
    'claude-code' => managedProviders.quickPresetClaudeCodeHint,
    'cursor' => managedProviders.quickPresetCursorHint,
    'codebuddy' => managedProviders.quickPresetCodebuddyHint,
    'deepseek' => managedProviders.quickPresetDeepSeekHint,
    'opencode-go' => managedProviders.quickPresetOpencodeGoHint,
    'qoder' => managedProviders.quickPresetQoderHint,
    'qoder-cn' => managedProviders.quickPresetQoderCnHint,
    kManagedProviderQuickPresetCustomId =>
      managedProviders.quickPresetCustomHint,
    _ => '',
  };

  String managedProviderKindLabel(ManagedProviderKind kind) => switch (kind) {
    ManagedProviderKind.apiBalance => managedProviders.kindApiBalance,
    ManagedProviderKind.subscriptionQuota =>
      managedProviders.kindSubscriptionQuota,
    ManagedProviderKind.customHttp => managedProviders.kindCustomHttp,
    ManagedProviderKind.unknown => kind.value,
  };
}

// `BuildContextL10n` (context.l10n) lives in l10n_compat.dart and is exposed
// through the app_localizations.dart re-export below.

extension EditorL10n on AppLocalizations {
  String editorSnackbarMessage(String code) {
    final diff = diffEditorSnackbarMessage(code);
    if (diff != null) return diff;
    if (code.startsWith(EditorMessage.saveFailedPrefix)) {
      final detail = code.substring(EditorMessage.saveFailedPrefix.length);
      return editor.saveFailed(error: detail);
    }
    return switch (code) {
      EditorMessage.binaryFile => editor.binaryFileHint,
      EditorMessage.readOnly => editor.fileReadOnly,
      EditorMessage.fileNotFound => editor.fileNotFound,
      EditorMessage.fileTooLarge => editor.fileTooLarge,
      EditorMessage.imageTooLarge => editor.imageTooLarge,
      EditorMessage.imageDecodeFailed => editor.imageDecodeFailed,
      EditorMessage.couldNotRead => editor.couldNotReadFile,
      _ => code,
    };
  }

  String editorPanelErrorMessage(String code) => editorSnackbarMessage(code);

  /// Localized text for diff-editor snackbar codes, or null when unrelated.
  String? diffEditorSnackbarMessage(String code) {
    if (code == 'diff.reloadAfterSaveFailed') {
      return diff.reloadAfterSaveFailed;
    }
    if (code == 'diff.fileReloadedAfterDiffWrite') {
      return diff.fileReloadedAfterDiffWrite;
    }
    const applyPrefix = 'diff.applyFailed: ';
    if (code.startsWith(applyPrefix)) {
      return diff.applyFailed(error: code.substring(applyPrefix.length));
    }
    const savePrefix = 'diff.saveFailed: ';
    if (code.startsWith(savePrefix)) {
      return diff.saveFailed(error: code.substring(savePrefix.length));
    }
    return null;
  }
}

bool isDiffEditorSurfaceSnackbar(String code) =>
    const {
      'diff.reloadAfterSaveFailed',
      'diff.fileReloadedAfterDiffWrite',
    }.contains(code) ||
    code.startsWith('diff.applyFailed: ') ||
    code.startsWith('diff.saveFailed: ');
