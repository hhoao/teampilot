import 'package:flutter/foundation.dart';

@immutable
class FlashskySession {
  /// Default [display] for new sessions and UI fallback when [display] is empty.
  static const String kDefaultDisplayTitle = 'New Chat';

  const FlashskySession({
    required this.sessionId,
    this.cwd = '',
    this.startedAt = 0,
    this.kind = '',
    this.entrypoint = '',
    this.display = '',
    this.sessionTeam = '',
  });

  factory FlashskySession.fromJson(Map<String, Object?> json) {
    return FlashskySession(
      sessionId: json['sessionId'] as String? ?? '',
      cwd: json['cwd'] as String? ?? '',
      startedAt: json['startedAt'] as int? ?? 0,
      kind: json['kind'] as String? ?? '',
      entrypoint: json['entrypoint'] as String? ?? '',
      display: json['display'] as String? ?? '',
      sessionTeam: json['sessionTeam'] as String? ?? '',
    );
  }

  final String sessionId;
  final String cwd;
  final int startedAt;
  final String kind;
  final String entrypoint;
  final String display;
  final String sessionTeam;

  /// Title shown in tabs and session list ([display] or [kDefaultDisplayTitle]).
  String get displayTitle =>
      display.isNotEmpty ? display : kDefaultDisplayTitle;

  FlashskySession copyWith({
    String? sessionId,
    String? cwd,
    int? startedAt,
    String? kind,
    String? entrypoint,
    String? display,
    String? sessionTeam,
  }) {
    return FlashskySession(
      sessionId: sessionId ?? this.sessionId,
      cwd: cwd ?? this.cwd,
      startedAt: startedAt ?? this.startedAt,
      kind: kind ?? this.kind,
      entrypoint: entrypoint ?? this.entrypoint,
      display: display ?? this.display,
      sessionTeam: sessionTeam ?? this.sessionTeam,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'sessionId': sessionId,
      'cwd': cwd,
      'startedAt': startedAt,
      'kind': kind,
      'entrypoint': entrypoint,
      'display': display,
      'sessionTeam': sessionTeam,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FlashskySession &&
            runtimeType == other.runtimeType &&
            sessionId == other.sessionId &&
            cwd == other.cwd &&
            startedAt == other.startedAt &&
            kind == other.kind &&
            entrypoint == other.entrypoint &&
            display == other.display &&
            sessionTeam == other.sessionTeam;
  }

  @override
  int get hashCode => Object.hash(sessionId, cwd, startedAt, kind, entrypoint, display, sessionTeam);
}
