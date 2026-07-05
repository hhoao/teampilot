import 'package:flutter/foundation.dart';

/// Session-scoped snapshot of an expert persona at create time.
///
/// Merged into the personal stand-in member at connect without mutating
/// [PersonalProfile].
@immutable
class ExpertSessionOverlay {
  const ExpertSessionOverlay({
    required this.expertKey,
    required this.displayName,
    this.prompt = '',
    this.playbook = '',
  });

  final String expertKey;
  final String displayName;
  final String prompt;
  final String playbook;

  factory ExpertSessionOverlay.fromJson(Map<String, Object?> json) {
    return ExpertSessionOverlay(
      expertKey: json['expertKey'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      playbook: json['playbook'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'expertKey': expertKey,
    'displayName': displayName,
    if (prompt.isNotEmpty) 'prompt': prompt,
    if (playbook.isNotEmpty) 'playbook': playbook,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ExpertSessionOverlay &&
            runtimeType == other.runtimeType &&
            expertKey == other.expertKey &&
            displayName == other.displayName &&
            prompt == other.prompt &&
            playbook == other.playbook;
  }

  @override
  int get hashCode => Object.hash(expertKey, displayName, prompt, playbook);
}
