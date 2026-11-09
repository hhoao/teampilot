import '../../l10n/app_localizations.dart';
import 'launch_config_schema_fields.dart';
import 'shell_script_launch_schema.dart';

/// Localizes a launch-config schema field label for UI.
///
/// Known shell-script keys use arb strings; otherwise falls back to
/// [field.label] (schema `title` or title-cased key).
String localizeLaunchConfigFieldLabel(
  AppLocalizations l10n,
  LaunchConfigSchemaField field,
) {
  return switch (field.key) {
    'name' => l10n.run.configurationName,
    'command' => l10n.run.fieldCommand,
    'args' => l10n.run.fieldArgs,
    'env' => l10n.run.fieldEnv,
    'cwd' => l10n.run.fieldCwd,
    'shell' => l10n.run.fieldShell,
    'type' => l10n.run.configurationType,
    'scriptPath' => l10n.run.fieldScriptPath,
    'scriptText' => l10n.run.fieldScriptText,
    'execute' => l10n.run.fieldExecute,
    'scriptOptions' => l10n.run.fieldScriptOptions,
    'interpreterPath' => l10n.run.fieldInterpreterPath,
    'interpreterOptions' => l10n.run.fieldInterpreterOptions,
    'executeInTerminal' => l10n.run.fieldExecuteInTerminal,
    'allowMultipleInstances' => l10n.run.fieldAllowMultipleInstances,
    'activateToolWindow' => l10n.run.fieldActivateToolWindow,
    'focusToolWindow' => l10n.run.fieldFocusToolWindow,
    _ => field.label,
  };
}

/// Localizes a launch type id for type picker / type field display.
String localizeLaunchTypeLabel(AppLocalizations l10n, String type) {
  if (type == ShellScriptLaunchSchema.typeName) {
    return l10n.run.typeShellScript;
  }
  return type;
}

/// Localizes an enum option for a schema field (e.g. `execute`).
String localizeLaunchConfigEnumValue(
  AppLocalizations l10n,
  String fieldKey,
  String value,
) {
  if (fieldKey == 'execute') {
    return switch (value) {
      'scriptFile' => l10n.run.executeScriptFile,
      'scriptText' => l10n.run.executeScriptText,
      _ => value,
    };
  }
  return value;
}

/// Stable English validation codes emitted by launch schema validate.
abstract final class LaunchConfigValidationCodes {
  static const configurationMustBeMap = 'configuration must be a map';
  static const envMustBeStringMap = 'env must be a map of strings';
  static const cwdMustBeString = 'cwd must be a string';
}

/// Maps a shell-script validation code to a localized UI message.
String localizeLaunchConfigValidation(AppLocalizations l10n, String code) {
  return switch (code) {
    LaunchConfigValidationCodes.configurationMustBeMap =>
      l10n.run.validationConfigurationMustBeMap,
    LaunchConfigValidationCodes.envMustBeStringMap =>
      l10n.run.validationEnvMustBeStringMap,
    LaunchConfigValidationCodes.cwdMustBeString =>
      l10n.run.validationCwdMustBeString,
    ShellScriptValidationCodes.executeRequired =>
      l10n.run.validationExecuteRequired,
    ShellScriptValidationCodes.executeInvalid =>
      l10n.run.validationExecuteInvalid,
    ShellScriptValidationCodes.scriptPathRequired =>
      l10n.run.validationScriptPathRequired,
    ShellScriptValidationCodes.scriptTextRequired =>
      l10n.run.validationScriptTextRequired,
    ShellScriptValidationCodes.interpreterPathMustBeString =>
      l10n.run.validationInterpreterPathMustBeString,
    ShellScriptValidationCodes.executeInTerminalMustBeBoolean =>
      l10n.run.validationExecuteInTerminalMustBeBoolean,
    ShellScriptValidationCodes.allowMultipleInstancesMustBeBoolean =>
      l10n.run.validationAllowMultipleInstancesMustBeBoolean,
    ShellScriptValidationCodes.activateToolWindowMustBeBoolean =>
      l10n.run.validationActivateToolWindowMustBeBoolean,
    ShellScriptValidationCodes.focusToolWindowMustBeBoolean =>
      l10n.run.validationFocusToolWindowMustBeBoolean,
    _ => code,
  };
}

/// Localizes each segment of a joined validation error string.
String localizeLaunchConfigValidationJoined(
  AppLocalizations l10n,
  String joined,
) {
  return joined
      .split('; ')
      .map((part) => localizeLaunchConfigValidation(l10n, part.trim()))
      .join('; ');
}
