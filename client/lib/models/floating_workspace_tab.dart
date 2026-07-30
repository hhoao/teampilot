import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// One tab inside a workspace floating panel bucket.
@immutable
class FloatingTab extends Equatable {
  const FloatingTab({
    required this.id,
    required this.surfaceId,
    required this.title,
    this.payload,
  });

  final String id;
  final String surfaceId;
  final String title;
  final Object? payload;

  FloatingTab copyWith({
    String? id,
    String? surfaceId,
    String? title,
    Object? payload,
  }) {
    return FloatingTab(
      id: id ?? this.id,
      surfaceId: surfaceId ?? this.surfaceId,
      title: title ?? this.title,
      payload: payload ?? this.payload,
    );
  }

  @override
  List<Object?> get props => [id, surfaceId, title, payload];
}
