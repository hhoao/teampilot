import 'package:equatable/equatable.dart';

/// Delivery state for a user message persisted outside CLI transcripts.
enum FailedMessageStatus { sending, sent, failed }

/// A session-owned user message whose delivery state needs to survive restart.
class FailedMessageRecord extends Equatable {
  const FailedMessageRecord({
    required this.id,
    required this.text,
    required this.createdAt,
    this.status = FailedMessageStatus.sending,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final FailedMessageStatus status;

  FailedMessageRecord copyWith({
    String? id,
    String? text,
    DateTime? createdAt,
    FailedMessageStatus? status,
  }) => FailedMessageRecord(
    id: id ?? this.id,
    text: text ?? this.text,
    createdAt: createdAt ?? this.createdAt,
    status: status ?? this.status,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status.name,
  };

  static FailedMessageRecord? fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    final text = json['text'] as String?;
    final createdAtRaw = json['createdAt'] as String?;
    final statusRaw = json['status'] as String?;
    final createdAt = createdAtRaw == null
        ? null
        : DateTime.tryParse(createdAtRaw);
    final status = statusRaw == null
        ? null
        : FailedMessageStatus.values
              .where((value) => value.name == statusRaw)
              .firstOrNull;
    if (id == null || text == null || createdAt == null || status == null) {
      return null;
    }
    return FailedMessageRecord(
      id: id,
      text: text,
      createdAt: createdAt.toUtc(),
      status: status,
    );
  }

  @override
  List<Object?> get props => [id, text, createdAt, status];
}
