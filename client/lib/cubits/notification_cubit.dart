import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/app_notification.dart';
import '../repositories/notification_repository.dart';
import '../services/notification/notification_recorder.dart';
import '../services/storage/app_storage.dart';
import '../theme/app_toast_theme.dart';

class NotificationState extends Equatable {
  const NotificationState({this.items = const [], this.unreadCount = 0});

  final List<AppNotification> items;
  final int unreadCount;

  @override
  List<Object?> get props => [items, unreadCount];
}

class NotificationCubit extends Cubit<NotificationState>
    implements NotificationRecorder {
  NotificationCubit({NotificationRepository? repository})
    : _repository =
          repository ??
          NotificationRepository(
            fs: AppStorage.fs,
            storePath: AppStorage.paths.notificationsJson,
          ),
      super(const NotificationState());

  final NotificationRepository _repository;
  static const _uuid = Uuid();

  Future<void> load() async {
    final store = await _repository.load(forceReload: true);
    _emitFromStore(store);
  }

  @override
  void record({required String message, required AppToastVariant variant}) {
    if (variant == AppToastVariant.info) return;
    unawaited(_record(message: message, variant: variant));
  }

  Future<void> _record({
    required String message,
    required AppToastVariant variant,
  }) async {
    final store = await _repository.append(
      id: _uuid.v4(),
      message: message,
      variant: variant,
    );
    _emitFromStore(store);
  }

  Future<void> markRead(String id) async {
    final store = await _repository.markRead(id);
    _emitFromStore(store);
  }

  Future<void> markAllRead() async {
    final store = await _repository.markAllRead();
    _emitFromStore(store);
  }

  Future<void> delete(String id) async {
    final store = await _repository.delete(id);
    _emitFromStore(store);
  }

  Future<void> clearAll() async {
    final store = await _repository.clearAll();
    _emitFromStore(store);
  }

  void _emitFromStore(AppNotificationStore store) {
    final unread = store.items.where((item) => !item.isRead).length;
    emit(NotificationState(items: store.items, unreadCount: unread));
  }
}
