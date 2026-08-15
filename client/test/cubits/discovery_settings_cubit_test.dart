import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';

void main() {
  test('default state has autoRefresh disabled', () {
    final cubit = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    expect(cubit.state.autoRefreshEnabled, isFalse);
  });

  test('load() reads repository value', () async {
    final cubit = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(
        discoveryAutoRefreshEnabled: true,
      ),
    );
    await cubit.load();
    expect(cubit.state.autoRefreshEnabled, isTrue);
  });

  test('setAutoRefreshEnabled persists and updates state', () async {
    final repo = InMemoryAppSettingsRepository();
    final cubit = DiscoverySettingsCubit(repository: repo);
    await cubit.setAutoRefreshEnabled(true);
    expect(cubit.state.autoRefreshEnabled, isTrue);
    expect(await repo.loadDiscoveryAutoRefreshEnabled(), isTrue);
  });
}
