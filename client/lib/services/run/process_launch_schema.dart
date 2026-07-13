import '../../models/run/launch_configuration.dart';
import 'launch_config_l10n.dart';

/// Built-in JSON schema fields for `type: process` launch configurations.
abstract final class ProcessLaunchSchema {
  static const typeName = 'process';

  /// JSON-schema-shaped description for UI validation and documentation.
  static const configurationSchema = <String, Object?>{
    'type': 'object',
    'required': ['command'],
    'properties': {
      'command': {'type': 'string'},
      'args': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'env': {
        'type': 'object',
        'additionalProperties': {'type': 'string'},
      },
      'cwd': {'type': 'string'},
      'shell': {'type': 'boolean'},
    },
  };

  /// Validates a launch configuration map or [LaunchConfiguration].
  ///
  /// Returns stable English codes ([LaunchConfigValidationCodes]); empty when
  /// valid. Localize with [localizeLaunchConfigValidation] before showing UI.
  static List<String> validate(Object? configuration) {
    final map = _asMap(configuration);
    if (map == null) {
      return const [LaunchConfigValidationCodes.configurationMustBeMap];
    }

    final errors = <String>[];
    final command = map['command'];
    if (command is! String || command.trim().isEmpty) {
      errors.add(LaunchConfigValidationCodes.commandRequired);
    }

    final args = map['args'];
    if (args != null && args is! List) {
      errors.add(LaunchConfigValidationCodes.argsMustBeStringList);
    } else if (args is List && args.any((e) => e is! String)) {
      errors.add(LaunchConfigValidationCodes.argsMustBeStringList);
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

    final shell = map['shell'];
    if (shell != null && shell is! bool) {
      errors.add(LaunchConfigValidationCodes.shellMustBeBoolean);
    }

    return errors;
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
