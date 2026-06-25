import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/team_config.dart';
import '../services/cli/member_config/member_config_detail.dart';
import '../services/cli/member_config/member_config_inspector.dart';
import '../services/storage/runtime_context.dart';
import '../utils/logger.dart';

enum MemberConfigStatus { idle, loading, loaded, error }

class MemberConfigState {
  const MemberConfigState({
    this.status = MemberConfigStatus.idle,
    this.detail,
    this.workContext,
  });

  final MemberConfigStatus status;
  final MemberConfigDetail? detail;
  final RuntimeContext? workContext;

  MemberConfigState copyWith({
    MemberConfigStatus? status,
    MemberConfigDetail? detail,
    RuntimeContext? workContext,
  }) =>
      MemberConfigState(
        status: status ?? this.status,
        detail: detail ?? this.detail,
        workContext: workContext ?? this.workContext,
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
    required TeamProfile team,
    required TeamMemberConfig member,
    RuntimeContext? workContext,
  }) async {
    emit(state.copyWith(status: MemberConfigStatus.loading));
    try {
      final detail = await _inspector.inspect(
        workspaceId: workspaceId,
        sessionId: sessionId,
        team: team,
        member: member,
        workContext: workContext,
      );
      if (isClosed) return;
      emit(MemberConfigState(
        status: MemberConfigStatus.loaded,
        detail: detail,
        workContext: workContext,
      ));
    } on Object catch (e, st) {
      appLogger.w('[member-config] inspect failed: $e', stackTrace: st);
      if (isClosed) return;
      emit(state.copyWith(status: MemberConfigStatus.error));
    }
  }
}
