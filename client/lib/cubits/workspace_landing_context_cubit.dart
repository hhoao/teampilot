import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/landing_launch_context.dart';
import '../models/workspace.dart';

class WorkspaceLandingContextState {
  const WorkspaceLandingContextState({
    required this.context,
    this.initialized = false,
  });

  final LandingLaunchContext context;
  final bool initialized;

  WorkspaceLandingContextState copyWith({
    LandingLaunchContext? context,
    bool? initialized,
  }) {
    return WorkspaceLandingContextState(
      context: context ?? this.context,
      initialized: initialized ?? this.initialized,
    );
  }
}

/// Per-workspace **manage / chrome** profile (route `?profile=` + manage bar).
/// Compose-landing drafts are local to [WorkspaceChatLanding] and must not
/// update this cubit.
class WorkspaceLandingContextCubit extends Cubit<WorkspaceLandingContextState> {
  WorkspaceLandingContextCubit({
    required this.workspaceId,
    LandingLaunchContext? initial,
  }) : super(
         WorkspaceLandingContextState(
           context:
               initial ??
               const LandingLaunchContext(isPersonal: true),
         ),
       );

  final String workspaceId;

  Future<void> initialize(Workspace workspace) async {
    if (state.initialized) return;
    emit(
      const WorkspaceLandingContextState(
        initialized: true,
        context: LandingLaunchContext(isPersonal: true),
      ),
    );
  }

  void update(LandingLaunchContext context) {
    emit(state.copyWith(context: context, initialized: true));
  }
}
