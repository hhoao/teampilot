import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_global_section.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_route.dart';

void main() {
  test('managedProviders has an independent home deep link', () {
    expect(
      HomeGlobalView.fromSegment('managedProviders'),
      HomeGlobalView.managedProviders,
    );
    expect(
      HomeGlobalView.managedProviders.homeLocation,
      '/home-v2?global=managedProviders',
    );
    expect(
      HomeWorkspaceRoute.homeGlobalView('/home-v2?global=managedProviders'),
      HomeGlobalView.managedProviders,
    );
  });

  test('CLI providers remain a separate global view', () {
    expect(HomeGlobalView.fromSegment('providers'), HomeGlobalView.providers);
    expect(
      HomeWorkspaceRoute.homeGlobalView('/home-v2?global=providers'),
      HomeGlobalView.providers,
    );
  });
}
