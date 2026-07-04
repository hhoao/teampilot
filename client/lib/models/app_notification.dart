import 'package:equatable/equatable.dart';

import '../theme/app_toast_theme.dart';

/// Persisted app-level notification (from [AppToast], excluding info).
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.variant,
    required this.message,
    required this.createdAt,
    this.title = '',
    this.isRead = false,
  });

  final String id;
  final AppToastVariant variant;
  /// Optional headline (e.g. session name). Empty for legacy toast-only rows.
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;

  bool get hasTitle => title.trim().isNotEmpty;

  AppNotification copyWith({
    String? id,
    AppToastVariant? variant,
    String? title,
    String? message,
    DateTime? createdAt,
    bool? isRead,
  }) {
    return AppNotification(
      id: id ?? this.id,
      variant: variant ?? this.variant,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'variant': variant.name,
    if (title.trim().isNotEmpty) 'title': title.trim(),
    'message': message,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'isRead': isRead,
  };

  static AppNotification? fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString();
    final message = json['message']?.toString();
    final variantRaw = json['variant']?.toString();
    final createdRaw = json['createdAt']?.toString();
    if (id == null || message == null || variantRaw == null || createdRaw == null) {
      return null;
    }
    final variant = _parseVariant(variantRaw);
    if (variant == null) return null;
    final createdAt = DateTime.tryParse(createdRaw);
    if (createdAt == null) return null;
    return AppNotification(
      id: id,
      variant: variant,
      title: json['title']?.toString().trim() ?? '',
      message: message,
      createdAt: createdAt.toLocal(),
      isRead: json['isRead'] == true,
    );
  }

  @override
  List<Object?> get props => [id, variant, title, message, createdAt, isRead];
}

class AppNotificationStore extends Equatable {
  const AppNotificationStore({this.version = 1, this.items = const []});

  final int version;
  final List<AppNotification> items;

  AppNotificationStore copyWith({
    int? version,
    List<AppNotification>? items,
  }) {
    return AppNotificationStore(
      version: version ?? this.version,
      items: items ?? this.items,
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'items': items.map((e) => e.toJson()).toList(),
  };

  static AppNotificationStore fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    final items = <AppNotification>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map) {
          final parsed = AppNotification.fromJson(entry.cast<String, Object?>());
          if (parsed != null) items.add(parsed);
        }
      }
    }
    return AppNotificationStore(
      version: json['version'] is int ? json['version'] as int : 1,
      items: items,
    );
  }

  @override
  List<Object?> get props => [version, items];
}

AppToastVariant? _parseVariant(String raw) {
  for (final variant in AppToastVariant.values) {
    if (variant.name == raw && variant != AppToastVariant.info) {
      return variant;
    }
  }
  return null;
}
