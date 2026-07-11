import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/config_cubit.dart';

void main() {
  test('config cubit navigates sections', () {
    final cubit = ConfigCubit();
    expect(cubit.state.section, ConfigSection.layout);

    cubit.selectSection(ConfigSection.session);
    expect(cubit.state.section, ConfigSection.session);

    cubit.selectSection(ConfigSection.layout);
    expect(cubit.state.section, ConfigSection.layout);
  });
}
