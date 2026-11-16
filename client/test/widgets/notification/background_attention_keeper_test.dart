import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/notification/background_attention_service.dart';
import 'package:teampilot/widgets/notification/background_attention_keeper.dart';

class _RecordingService extends BackgroundAttentionService {
  _RecordingService() : super(isAndroid: false);

  final values = <bool>[];

  @override
  Future<void> setEnabled(bool enabled) async {
    values.add(enabled);
  }
}

void main() {
  testWidgets('mirrors the idle notification preference into the keeper', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cubit = SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
    );
    final service = _RecordingService();

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: BackgroundAttentionKeeper(
          service: service,
          child: const SizedBox(),
        ),
      ),
    );

    expect(service.values, [true]);

    await cubit.setNotifyOnSessionIdle(false);
    await tester.pump();

    expect(service.values, [true, false]);
    await cubit.close();
  });
}
