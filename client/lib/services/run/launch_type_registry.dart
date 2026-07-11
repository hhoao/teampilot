import '../../models/run/launch_type_contribution.dart';
import 'process_launch_schema.dart';

/// Result of registering an extension launch type.
class LaunchTypeRegisterResult {
  const LaunchTypeRegisterResult({required this.isConflict});

  final bool isConflict;
}

/// Registry of built-in and extension-provided launch types.
class LaunchTypeRegistry {
  LaunchTypeRegistry._();

  final Map<String, LaunchTypeContribution> _types = {};

  factory LaunchTypeRegistry.withBuiltIns() {
    final registry = LaunchTypeRegistry._();
    registry._types[ProcessLaunchSchema.typeName] = LaunchTypeContribution(
      type: ProcessLaunchSchema.typeName,
      kinds: const ['run'],
      adapterCommand: '',
      adapterRuntime: 'workspace',
      lifecycle: LaunchAdapterLifecycle.sticky,
      configurationSchema: Map<String, Object?>.from(
        ProcessLaunchSchema.configurationSchema,
      ),
    );
    return registry;
  }

  LaunchTypeContribution? get(String type) => _types[type];

  /// Registers an extension contribution. Built-in types cannot be overridden.
  ///
  /// When two extensions claim the same [LaunchTypeContribution.type], the
  /// first registration wins and later calls return [LaunchTypeRegisterResult.isConflict].
  LaunchTypeRegisterResult registerExtension(LaunchTypeContribution contribution) {
    if (contribution.adapterRuntime != 'workspace') {
      return const LaunchTypeRegisterResult(isConflict: true);
    }

    final existing = _types[contribution.type];
    if (existing != null) {
      if (existing.extensionId == null) {
        return const LaunchTypeRegisterResult(isConflict: true);
      }
      if (existing.extensionId != contribution.extensionId) {
        return const LaunchTypeRegisterResult(isConflict: true);
      }
      return const LaunchTypeRegisterResult(isConflict: false);
    }

    _types[contribution.type] = contribution;
    return const LaunchTypeRegisterResult(isConflict: false);
  }

  /// Whether [type] can run on [targetId].
  ///
  /// Stub until Task 7 probes extension adapter binaries on the target:
  /// built-in `process` is always available; extension types return false.
  bool isAvailable(String type, {required String targetId}) {
    if (type == ProcessLaunchSchema.typeName) return true;
    final contribution = _types[type];
    if (contribution == null || contribution.extensionId == null) {
      return false;
    }
    return false;
  }
}
