import '../../l10n/app_localizations.dart';
import 'launch_config_schema_fields.dart';
import 'shell_script_launch_schema.dart';

/// Localizes a launch-config schema field label for UI.
///
/// Known process/shell-script keys use arb strings; otherwise falls back to
/// [field.label] (schema `title` or title-cased key).
String localizeLaunchConfigFieldLabel(
  AppLocalizations l10n,
  LaunchConfigSchemaField field,
) {
  return switch (field.key) {
    'name' => l10n.runConfigurationName,
    'command' => l10n.runFieldCommand,
    'args' => l10n.runFieldArgs,
    'env' => l10n.runFieldEnv,
    'cwd' => l10n.runFieldCwd,
    'shell' => l10n.runFieldShell,
    'type' => l10n.runConfigurationType,
    'scriptPath' => l10n.runFieldScriptPath,
    'scriptText' => l10n.runFieldScriptText,
    'execute' => l10n.runFieldExecute,
    'scriptOptions' => l10n.runFieldScriptOptions,
    'interpreterPath' => l10n.runFieldInterpreterPath,
    'interpreterOptions' => l10n.runFieldInterpreterOptions,
    'executeInTerminal' => l10n.runFieldExecuteInTerminal,
    'allowMultipleInstances' => l10n.runFieldAllowMultipleInstances,
    'activateToolWindow' => l10n.runFieldActivateToolWindow,
    'focusToolWindow' => l10n.runFieldFocusToolWindow,
    _ => field.label,
  };
}

/// Localizes a launch type id for type picker / type field display.
String localizeLaunchTypeLabel(AppLocalizations l10n, String type) {
  if (type == ShellScriptLaunchSchema.typeName ||
      type == ShellScriptLaunchSchema.processAlias) {
    return l10n.runTypeShellScript;
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
      'scriptFile' => l10n.runExecuteScriptFile,
      'scriptText' => l10n.runExecuteScriptText,
      _ => value,
    };
  }
  return value;
}

/// Stable English validation codes emitted by process launch schema validate.
abstract final class LaunchConfigValidationCodes {
  static const configurationMustBeMap = 'configuration must be a map';
  static const commandRequired = 'command is required';
  static const argsMustBeStringList = 'args must be a list of strings';
  static const envMustBeStringMap = 'env must be a map of strings';
  static const cwdMustBeString = 'cwd must be a string';
  static const shellMustBeBoolean = 'shell must be a boolean';
}

/// Maps a process/shell-script validation code to a localized UI message.
String localizeLaunchConfigValidation(
  AppLocalizations l10n,
  String code,
) {
  return switch (code) {
    LaunchConfigValidationCodes.configurationMustBeMap =>
      l10n.runValidationConfigurationMustBeMap,
    LaunchConfigValidationCodes.commandRequired =>
      l10n.runValidationCommandRequired,
    LaunchConfigValidationCodes.argsMustBeStringList =>
      l10n.runValidationArgsMustBeStringList,
    LaunchConfigValidationCodes.envMustBeStringMap =>
      l10n.runValidationEnvMustBeStringMap,
    LaunchConfigValidationCodes.cwdMustBeString =>
      l10n.runValidationCwdMustBeString,
    LaunchConfigValidationCodes.shellMustBeBoolean =>
      l10n.runValidationShellMustBeBoolean,
    ShellScriptValidationCodes.executeRequired =>
      l10n.runValidationExecuteRequired,
    ShellScriptValidationCodes.executeInvalid =>
      l10n.runValidationExecuteInvalid,
    ShellScriptValidationCodes.scriptPathRequired =>
      l10n.runValidationScriptPathRequired,
    ShellScriptValidationCodes.scriptTextRequired =>
      l10n.runValidationScriptTextRequired,
    ShellScriptValidationCodes.interpreterPathMustBeString =>
      l10n.runValidationInterpreterPathMustBeString,
    ShellScriptValidationCodes.executeInTerminalMustBeBoolean =>
      l10n.runValidationExecuteInTerminalMustBeBoolean,
    ShellScriptValidationCodes.allowMultipleInstancesMustBeBoolean =>
      l10n.runValidationAllowMultipleInstancesMustBeBoolean,
    ShellScriptValidationCodes.activateToolWindowMustBeBoolean =>
      l10n.runValidationActivateToolWindowMustBeBoolean,
    ShellScriptValidationCodes.focusToolWindowMustBeBoolean =>
      l10n.runValidationFocusToolWindowMustBeBoolean,
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
