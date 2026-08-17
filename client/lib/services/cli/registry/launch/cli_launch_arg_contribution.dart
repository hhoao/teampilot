import 'package:meta/meta.dart';

/// The ordering bucket for a launch argument contribution.
enum LaunchArgPhase {
  command,
  session,
  workspace,
  identity,
  model,
  behavior,
  security,
  prompt,
  user,
}

/// Immutable semantic fragment of a CLI launch command.
@immutable
final class CliLaunchArgContribution {
  CliLaunchArgContribution({
    required this.key,
    required this.phase,
    required List<String> args,
    this.exclusiveGroup,
  }) : args = List.unmodifiable(args);

  /// Identifies the semantic contribution, rather than an option token.
  final String key;
  final LaunchArgPhase phase;
  final List<String> args;
  final String? exclusiveGroup;

  @override
  bool operator ==(Object other) {
    return other is CliLaunchArgContribution &&
        other.key == key &&
        other.phase == phase &&
        other.exclusiveGroup == exclusiveGroup &&
        _listEquals(other.args, args);
  }

  @override
  int get hashCode =>
      Object.hash(key, phase, exclusiveGroup, Object.hashAll(args));

  @override
  String toString() {
    return 'CliLaunchArgContribution('
        'key: $key, phase: $phase, args: $args, '
        'exclusiveGroup: $exclusiveGroup)';
  }
}

bool _listEquals(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
