import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/team_config.dart';
import '../services/cli/member_config/member_config_detail.dart';
import '../services/cli/member_config/member_config_inspector.dart';
import '../utils/logger.dart';

enum MemberConfigStatus { idle, loading, loaded, error }

class MemberConfigState {
  const MemberConfigState({
    this.status = MemberConfigStatus.idle,
    this.detail,
  });

  final MemberConfigStatus status;
  final MemberConfigDetail? detail;

  MemberConfigState copyWith({
    MemberConfigStatus? status,
    MemberConfigDetail? detail,
  }) =>
      MemberConfigState(
        status: status ?? this.status,
        detail: detail ?? this.detail,
      );
}

class MemberConfigCubit extends Cubit<MemberConfigState> {
  MemberConfigCubit({MemberConfigInspector? inspector})
      : _inspector = inspector ?? MemberConfigInspector(),
        super(const MemberConfigState());

  final MemberConfigInspector _inspector;

  Future<void> load({
    required String workspaceId,
    required String sessionId,
    required TeamIdentity team,
    required TeamMemberConfig member,
  }) async {
    emit(state.copyWith(status: MemberConfigStatus.loading));
    try {
      final detail = await _inspector.inspect(
        workspaceId: workspaceId,
        sessionId: sessionId,
        team: team,
        member: member,
      );
      if (isClosed) return;
      emit(MemberConfigState(
        status: MemberConfigStatus.loaded,
        detail: detail,
      ));
    } on Object catch (e, st) {
      appLogger.w('[member-config] inspect failed: $e', stackTrace: st);
      if (isClosed) return;
      emit(state.copyWith(status: MemberConfigStatus.error));
    }
  }
}
