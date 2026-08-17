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
  const CliLaunchArgContribution({
    required this.key,
    required this.phase,
    required List<String> args,
    this.exclusiveGroup,
  }) : _args = args;

  /// Identifies the semantic contribution, rather than an option token.
  final String key;
  final LaunchArgPhase phase;
  final List<String> _args;
  final String? exclusiveGroup;

  /// The contribution tokens, exposed without allowing list mutation.
  List<String> get args => List.unmodifiable(_args);

  @override
  bool operator ==(Object other) {
    return other is CliLaunchArgContribution &&
        other.key == key &&
        other.phase == phase &&
        other.exclusiveGroup == exclusiveGroup &&
        _listEquals(other._args, _args);
  }

  @override
  int get hashCode =>
      Object.hash(key, phase, exclusiveGroup, Object.hashAll(_args));

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
