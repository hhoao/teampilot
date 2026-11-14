import 'package:flutter/material.dart';

/// Bootstrap gate UI. On desktop the native splash covers this until bootstrap
/// completes; on Android [flutter_native_splash] covers it until [dismissBootSplash].
class AppBootstrapLoadingPage extends StatelessWidget {
  const AppBootstrapLoadingPage({super.key});

  // High-res (1024px) artwork shared with the Android 12 splash. At width 256
  // the image is downscaled rather than magnified, so the mark stays sharp on
  // dense screens; icon.svg is the vector original. See pubspec.yaml for the
  // pre-12 variant.
  static const _splashLogo = 'assets/icons/icon_splash_hd.png';

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
