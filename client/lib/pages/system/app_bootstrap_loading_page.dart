import 'package:flutter/material.dart';

/// Bootstrap gate UI. On desktop the native splash covers this until bootstrap
/// completes; on Android [flutter_native_splash] covers it until [dismissBootSplash].
class AppBootstrapLoadingPage extends StatelessWidget {
  const AppBootstrapLoadingPage({super.key});

  static const _splashLogo = 'assets/icons/icon_bg.png';

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFFFFFF),
      body: Center(
        child: Image(
          image: AssetImage(_splashLogo),
          width: 256,
          height: 256,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
