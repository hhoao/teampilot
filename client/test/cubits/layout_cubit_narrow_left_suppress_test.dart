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

  group('LayoutCubit narrow left suppress', () {
    test('defaults false', () {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);
      expect(cubit.state.narrowLeftSuppressed, isFalse);
    });

    test('setNarrowLeftSuppressed does not change sidebarVisible', () async {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);
      await cubit.setSidebarVisible(true);
      cubit.setNarrowLeftSuppressed(true);
      expect(cubit.state.narrowLeftSuppressed, isTrue);
      expect(cubit.state.preferences.sidebarVisible, isTrue);
    });

    test('setNarrowLeftSuppressed does not call repository save', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = _RecordingLayoutRepository(
        const LayoutPreferences(sidebarVisible: true),
        prefs,
      );
      final cubit = LayoutCubit(repository: repo);
      addTearDown(cubit.close);
      await cubit.load();

      cubit.setNarrowLeftSuppressed(true);
      expect(cubit.state.narrowLeftSuppressed, isTrue);
      expect(cubit.state.preferences.sidebarVisible, isTrue);
      expect(repo.saveCount, 0);
    });

    test('clearNarrowLeftSuppressed', () {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);
      cubit.setNarrowLeftSuppressed(true);
      cubit.clearNarrowLeftSuppressed();
      expect(cubit.state.narrowLeftSuppressed, isFalse);
    });
  });
}
