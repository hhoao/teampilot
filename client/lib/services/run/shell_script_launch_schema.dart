import '../../models/run/launch_configuration.dart';
import '../host/host_interactive_shell.dart';
import 'launch_config_l10n.dart';

/// Stable English validation codes for [ShellScriptLaunchSchema.validate].
///
/// Shared codes reuse [LaunchConfigValidationCodes]; shell-specific codes live
/// here.
abstract final class ShellScriptValidationCodes {
  static const executeRequired = 'execute is required';
  static const executeInvalid = 'execute must be scriptFile or scriptText';
  static const scriptPathRequired = 'scriptPath is required';
  static const scriptTextRequired = 'scriptText is required';
  static const interpreterPathMustBeString = 'interpreterPath must be a string';
  static const executeInTerminalMustBeBoolean =
      'executeInTerminal must be a boolean';
  static const allowMultipleInstancesMustBeBoolean =
      'allowMultipleInstances must be a boolean';
  static const activateToolWindowMustBeBoolean =
      'activateToolWindow must be a boolean';
  static const focusToolWindowMustBeBoolean = 'focusToolWindow must be a boolean';
}

/// Built-in JSON schema fields for `type: shellScript` launch configurations.
abstract final class ShellScriptLaunchSchema {
  static const typeName = 'shellScript';
  static const processAlias = 'process';

  static const _defaultCwd = r'${workspaceFolder}';

  /// Platform default interactive shell executable.
  static String defaultInterpreterPath() =>
      HostInteractiveShell.defaultExecutable();

  /// JSON-schema-shaped description for UI validation and documentation.
  static const configurationSchema = <String, Object?>{
    'type': 'object',
    'required': ['execute'],
    'properties': {
      'execute': {
        'type': 'string',
        'enum': ['scriptFile', 'scriptText'],
      },
      'scriptPath': {'type': 'string', 'title': 'Script path'},
      'scriptText': {'type': 'string', 'title': 'Script text'},
      'scriptOptions': {'type': 'string'},
      'interpreterPath': {'type': 'string'},
      'interpreterOptions': {'type': 'string'},
      'cwd': {'type': 'string'},
      'env': {
        'type': 'object',
        'additionalProperties': {'type': 'string'},
      },
      'executeInTerminal': {'type': 'boolean'},
      'allowMultipleInstances': {'type': 'boolean'},
      'activateToolWindow': {'type': 'boolean'},
      'focusToolWindow': {'type': 'boolean'},
    },
  };

  /// Fills IDEA-aligned defaults for a new or partial shellScript map.
  ///
  /// Existing keys win; missing keys get schema defaults (including
  /// [defaultInterpreterPath] and `${workspaceFolder}` cwd).
  static Map<String, Object?> withDefaults(Map<String, Object?> raw) {
    return {
      'execute': 'scriptFile',
      'scriptOptions': '',
      'interpreterOptions': '',
      'env': <String, Object?>{},
      'executeInTerminal': true,
      'allowMultipleInstances': false,
      'activateToolWindow': true,
      'focusToolWindow': false,
      'interpreterPath': defaultInterpreterPath(),
      'cwd': _defaultCwd,
      ...raw,
      if (raw['cwd'] == null ||
          (raw['cwd'] is String && (raw['cwd'] as String).trim().isEmpty))
        'cwd': _defaultCwd,
      if (raw['interpreterPath'] == null ||
          (raw['interpreterPath'] is String &&
              (raw['interpreterPath'] as String).trim().isEmpty))
        'interpreterPath': defaultInterpreterPath(),
      if (raw['scriptOptions'] == null) 'scriptOptions': '',
      if (raw['interpreterOptions'] == null) 'interpreterOptions': '',
      if (raw['env'] == null) 'env': <String, Object?>{},
    };
  }

  /// Validates a launch configuration map or [LaunchConfiguration].
  ///
  /// Returns stable English codes ([ShellScriptValidationCodes] /
  /// [LaunchConfigValidationCodes]); empty when valid.
  static List<String> validate(Object? configuration) {
    final map = _asMap(configuration);
    if (map == null) {
      return const [LaunchConfigValidationCodes.configurationMustBeMap];
    }

    final errors = <String>[];
    final execute = map['execute'];
    if (execute is! String || execute.trim().isEmpty) {
      errors.add(ShellScriptValidationCodes.executeRequired);
    } else if (execute != 'scriptFile' && execute != 'scriptText') {
      errors.add(ShellScriptValidationCodes.executeInvalid);
    } else if (execute == 'scriptFile') {
      final scriptPath = map['scriptPath'];
      if (scriptPath is! String || scriptPath.trim().isEmpty) {
        errors.add(ShellScriptValidationCodes.scriptPathRequired);
      }
    } else if (execute == 'scriptText') {
      final scriptText = map['scriptText'];
      if (scriptText is! String || scriptText.trim().isEmpty) {
        errors.add(ShellScriptValidationCodes.scriptTextRequired);
      }
    }

    final env = map['env'];
    if (env != null) {
      if (env is! Map) {
        errors.add(LaunchConfigValidationCodes.envMustBeStringMap);
      } else if (env.entries.any((e) => e.value is! String)) {
        errors.add(LaunchConfigValidationCodes.envMustBeStringMap);
      }
    }

    final cwd = map['cwd'];
    if (cwd != null && cwd is! String) {
      errors.add(LaunchConfigValidationCodes.cwdMustBeString);
    }

    final interpreterPath = map['interpreterPath'];
    if (interpreterPath != null && interpreterPath is! String) {
      errors.add(ShellScriptValidationCodes.interpreterPathMustBeString);
    }

    _requireBool(
      map,
      'executeInTerminal',
      ShellScriptValidationCodes.executeInTerminalMustBeBoolean,
      errors,
    );
    _requireBool(
      map,
      'allowMultipleInstances',
      ShellScriptValidationCodes.allowMultipleInstancesMustBeBoolean,
      errors,
    );
    _requireBool(
      map,
      'activateToolWindow',
      ShellScriptValidationCodes.activateToolWindowMustBeBoolean,
      errors,
    );
    _requireBool(
      map,
      'focusToolWindow',
      ShellScriptValidationCodes.focusToolWindowMustBeBoolean,
      errors,
    );

    return errors;
  }

  static void _requireBool(
    Map<String, Object?> map,
    String key,
    String code,
    List<String> errors,
  ) {
    final value = map[key];
    if (value != null && value is! bool) {
      errors.add(code);
    }
  }

  static Map<String, Object?>? _asMap(Object? configuration) {
    if (configuration is LaunchConfiguration) {
      return configuration.toJson();
    }
    if (configuration is Map) {
      return configuration.cast<String, Object?>();
    }
    return null;
  }
}
