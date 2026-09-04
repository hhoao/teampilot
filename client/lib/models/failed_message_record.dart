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
    this.deliveryId,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final FailedMessageStatus status;

  /// Durable prompt-delivery correlation for workflow-owned sends.
  final String? deliveryId;

  FailedMessageRecord copyWith({
    String? id,
    String? text,
    DateTime? createdAt,
    FailedMessageStatus? status,
    String? deliveryId,
    bool clearDeliveryId = false,
  }) => FailedMessageRecord(
    id: id ?? this.id,
    text: text ?? this.text,
    createdAt: createdAt ?? this.createdAt,
    status: status ?? this.status,
    deliveryId: clearDeliveryId ? null : deliveryId ?? this.deliveryId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    if (deliveryId case final id? when id.isNotEmpty) 'deliveryId': id,
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
      deliveryId: json['deliveryId'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, text, createdAt, status, deliveryId];
}
