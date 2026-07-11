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

  /// Availability keyed by `type|targetId`. Set by [LaunchTypeRegistrar].
  final Map<String, bool> _availability = {};

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

  /// Removes extension-contributed types (keeps built-in `process`).
  void clearExtensions() {
    _types.removeWhere((_, value) => value.extensionId != null);
    _availability.clear();
  }

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

  /// Records whether [type] is available on [targetId] after detect/probe.
  void setAvailability(
    String type, {
    required String targetId,
    required bool available,
  }) {
    _availability[_availabilityKey(type, targetId)] = available;
  }

  /// Whether [type] can run on [targetId].
  ///
  /// Built-in `process` is always available. Extension types require a prior
  /// [setAvailability] (typically from [LaunchTypeRegistrar] after detect).
  /// Remote targets without an explicit availability entry are unavailable
  /// (v1: no host fallback / remote adapter provisioning).
  bool isAvailable(String type, {required String targetId}) {
    if (type == ProcessLaunchSchema.typeName) return true;
    final contribution = _types[type];
    if (contribution == null || contribution.extensionId == null) {
      return false;
    }
    return _availability[_availabilityKey(type, targetId)] == true;
  }

  static String _availabilityKey(String type, String targetId) =>
      '$type|$targetId';
}
