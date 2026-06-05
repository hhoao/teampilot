import 'package:equatable/equatable.dart';

/// One row in the mailbox feed: a team-bus message flattened for display.
class BusFeedEntry extends Equatable {
  const BusFeedEntry({
    required this.from,
    required this.to,
    required this.content,
    required this.createdAt,
    required this.isUnread,
  });

  final String from;
  final String to;
  final String content;
  final int createdAt;
  final bool isUnread;

  @override
  List<Object?> get props => [from, to, content, createdAt, isUnread];
}
