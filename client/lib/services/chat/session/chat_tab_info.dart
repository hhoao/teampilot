import 'package:equatable/equatable.dart';

class ChatTabInfo extends Equatable {
  const ChatTabInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    this.isRunning = false,
    this.launchError,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool isRunning;

  /// User-facing summary when the last connect attempt failed (placeholder P0).
  final String? launchError;

  ChatTabInfo copyWith({
    String? title,
    String? subtitle,
    bool? isRunning,
    String? launchError,
    bool clearLaunchError = false,
  }) {
    return ChatTabInfo(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      isRunning: isRunning ?? this.isRunning,
      launchError: clearLaunchError ? null : (launchError ?? this.launchError),
    );
  }

  @override
  List<Object?> get props => [id, title, subtitle, isRunning, launchError];
}
