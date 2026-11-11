/// The `tp_sshd_crypto_flutter` plugin: the Flutter build wiring for the
/// tp_sshd_crypto shim.
///
/// This package has no Dart API on purpose. Its pubspec declares the
/// `linux`, `windows`, `macos`, and `android` lanes as `ffiPlugin: true`, and
/// each lane's native build file compiles
/// `../dartssh2/native/tp_sshd_crypto.c` (the dartssh2 package's copy — never
/// duplicated here) into the shared library that ships in the app bundle:
/// `libtp_sshd_crypto.so` on Linux and Android, `libtp_sshd_crypto.dylib` on
/// macOS, `tp_sshd_crypto.dll` on Windows.
///
/// The library is bound by `package:dartssh2`, not by anything in this
/// package: `dartssh2/lib/src/utils/native_crypto.dart` opens the shim by
/// that bare file name, which is what the OS loader resolves out of the app
/// bundle's library directory. A shim that is not bundled therefore cannot be
/// loaded, which is the failure this package exists to prevent.
library;
