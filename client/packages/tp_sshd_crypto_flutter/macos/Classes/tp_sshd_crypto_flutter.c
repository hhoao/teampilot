// Relative import to be able to reuse the C sources without copying them.
// See the comment in ../tp_sshd_crypto_flutter.podspec for more information.
//
// The shim's own source is the source of truth: this package compiles
// client/packages/dartssh2/native/tp_sshd_crypto.c, it does not own a copy.
#include "../../../dartssh2/native/tp_sshd_crypto.c"
