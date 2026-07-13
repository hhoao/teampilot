import '../../l10n/app_localizations.dart';
import 'launch_config_schema_fields.dart';

/// Localizes a launch-config schema field label for UI.
///
/// Known process keys use arb strings; otherwise falls back to [field.label]
/// (schema `title` or title-cased key).
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
    _ => field.label,
  };
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

/// Maps a process-schema validation code to a localized UI message.
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
