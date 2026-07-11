import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/repositories/layout_repository.dart';

class _RecordingLayoutRepository extends LayoutRepository {
  _RecordingLayoutRepository(this._initial, SharedPreferences prefs)
    : super(prefs);

  final LayoutPreferences _initial;
  int saveCount = 0;

  @override
  Future<LayoutPreferences> load() async => _initial;

  @override
  Future<void> save(LayoutPreferences preferences) async {
    saveCount++;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LayoutCubit landing right tools override', () {
    test('landing override does not change persisted rightToolsVisible', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = _RecordingLayoutRepository(
        const LayoutPreferences(rightToolsVisible: true),
        prefs,
      );
      final cubit = LayoutCubit(repository: repo);
      addTearDown(cubit.close);
      await cubit.load();

      cubit.setLandingRightToolsOverride(true);
      expect(cubit.state.landingRightToolsOverride, isTrue);
      expect(cubit.state.preferences.rightToolsVisible, isTrue);
      expect(repo.saveCount, 0);
    });

    test('toggleRightTools on compose flips override only', () async {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);
      final intent = cubit.state.preferences.rightToolsVisible;

      await cubit.toggleRightTools(composeLanding: true);
      expect(cubit.state.landingRightToolsOverride, isTrue);
      expect(cubit.state.preferences.rightToolsVisible, intent);

      await cubit.toggleRightTools(composeLanding: true);
      expect(cubit.state.landingRightToolsOverride, isFalse);
      expect(cubit.state.preferences.rightToolsVisible, intent);
    });

    test('toggleRightTools on session still flips prefs', () async {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);
      final initial = cubit.state.preferences.rightToolsVisible;
      await cubit.toggleRightTools(composeLanding: false);
      expect(cubit.state.preferences.rightToolsVisible, !initial);
      expect(cubit.state.landingRightToolsOverride, isNull);
    });

    test('clearLandingRightToolsOverride sets null', () {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);
      cubit.setLandingRightToolsOverride(true);
      cubit.clearLandingRightToolsOverride();
      expect(cubit.state.landingRightToolsOverride, isNull);
    });
  });
}
