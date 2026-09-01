import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/repositories/layout_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('layout cubit persists preferences', () async {
    final cubit = LayoutCubit(
      repository: LayoutRepository(await SharedPreferences.getInstance()),
    );
    await cubit.load();

    await cubit.setThemeMode('dark');
    expect(cubit.state.preferences.themeMode, 'dark');
  });

  test('setFoldToolCallCategory toggles and persists', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    await cubit.load();
    await cubit.setFoldToolCallCategory(
      AiToolCallCategory.subagent,
      fold: true,
    );
    expect(
      cubit.state.preferences.foldToolCallCategories.contains(
        AiToolCallCategory.subagent,
      ),
      isTrue,
    );
    await cubit.setFoldToolCallCategory(
      AiToolCallCategory.subagent,
      fold: false,
    );
    expect(
      cubit.state.preferences.foldToolCallCategories.contains(
        AiToolCallCategory.subagent,
      ),
      isFalse,
    );
  });

  test('setSessionTabBarVisible toggles and persists', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    await cubit.load();

    await cubit.setSessionTabBarVisible(false);
    expect(cubit.state.preferences.sessionTabBarVisible, isFalse);

    await cubit.setSessionTabBarVisible(true);
    expect(cubit.state.preferences.sessionTabBarVisible, isTrue);

    // Reload from the repository to prove persistence.
    final reloaded = LayoutCubit(repository: LayoutRepository(prefs));
    await reloaded.load();
    expect(reloaded.state.preferences.sessionTabBarVisible, isTrue);
  });
}
