import 'package:flashskyai_client/cubits/session_preferences_cubit.dart';
import 'package:flashskyai_client/repositories/session_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SessionPreferencesCubit> makeCubit({String? located}) async {
    final prefs = await SharedPreferences.getInstance();
    return SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
      locatedExecutable: located,
    );
  }

  test('resolveExecutable prefers user path over located path', () async {
    final cubit = await makeCubit(located: '/usr/local/bin/flashskyai');
    await cubit.load();
    await cubit.setCliExecutablePath('/opt/custom/flashskyai');

    expect(cubit.resolveExecutable(), '/opt/custom/flashskyai');
  });

  test('resolveExecutable falls back to located path when user path empty',
      () async {
    final cubit = await makeCubit(located: '/usr/local/bin/flashskyai');
    await cubit.load();

    expect(cubit.resolveExecutable(), '/usr/local/bin/flashskyai');
  });

  test('resolveExecutable falls back to bare flashskyai when nothing known',
      () async {
    final cubit = await makeCubit(located: null);
    await cubit.load();

    expect(cubit.resolveExecutable(), 'flashskyai');
  });

  test('setCliExecutablePath persists and emits new state', () async {
    final cubit = await makeCubit(located: null);
    await cubit.load();
    await cubit.setCliExecutablePath('/a/b/flashskyai');

    expect(cubit.state.preferences.cliExecutablePath, '/a/b/flashskyai');

    final cubit2 = await makeCubit(located: null);
    await cubit2.load();
    expect(cubit2.state.preferences.cliExecutablePath, '/a/b/flashskyai');
  });

  test('setAutoLaunchAllMembersOnConnect persists the flag', () async {
    final cubit = await makeCubit(located: null);
    await cubit.load();
    await cubit.setAutoLaunchAllMembersOnConnect(true);

    expect(cubit.state.preferences.autoLaunchAllMembersOnConnect, true);
  });

  test('setScopeSessionsToSelectedTeam persists the flag', () async {
    final cubit = await makeCubit(located: null);
    await cubit.load();
    await cubit.setScopeSessionsToSelectedTeam(true);

    expect(cubit.state.preferences.scopeSessionsToSelectedTeam, true);

    final cubit2 = await makeCubit(located: null);
    await cubit2.load();
    expect(cubit2.state.preferences.scopeSessionsToSelectedTeam, true);
  });

  test('setCliExecutablePath trims whitespace and treats blank as cleared',
      () async {
    final cubit = await makeCubit(located: '/located');
    await cubit.load();
    await cubit.setCliExecutablePath('   ');

    expect(cubit.state.preferences.cliExecutablePath, '');
    expect(cubit.resolveExecutable(), '/located');
  });
}
