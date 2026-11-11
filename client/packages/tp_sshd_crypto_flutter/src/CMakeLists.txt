# Android lane: compiles the dartssh2 shim and links it against the vendored
# static libcrypto for the ABI being built (android/vendor/<ANDROID_ABI>/).
# The NDK provides neither, which is why they are vendored; see README.md.
cmake_minimum_required(VERSION 3.10)

project(tp_sshd_crypto_flutter LANGUAGES C)

# Resolve through the plugin symlink the Flutter tool builds through (the same
# hazard the desktop lanes document), then walk to the sibling dartssh2 package.
get_filename_component(_tp_sshd_crypto_pkg_dir
  "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH
)
set(TP_SSHD_CRYPTO_SOURCE
  "${_tp_sshd_crypto_pkg_dir}/../dartssh2/native/tp_sshd_crypto.c"
)
if(NOT EXISTS "${TP_SSHD_CRYPTO_SOURCE}")
  message(FATAL_ERROR
    "tp_sshd_crypto_flutter: the dartssh2 shim source is missing at "
    "${TP_SSHD_CRYPTO_SOURCE}."
  )
endif()

set(TP_SSHD_CRYPTO_VENDOR "${_tp_sshd_crypto_pkg_dir}/android/vendor/${ANDROID_ABI}")
if(NOT EXISTS "${TP_SSHD_CRYPTO_VENDOR}/lib/libcrypto.a")
  message(FATAL_ERROR
    "tp_sshd_crypto_flutter: no vendored libcrypto for ABI '${ANDROID_ABI}' at "
    "${TP_SSHD_CRYPTO_VENDOR}. Only arm64-v8a and x86_64 are vendored; see "
    "README.md for the build recipe to add another."
  )
endif()

add_library(tp_sshd_crypto SHARED "${TP_SSHD_CRYPTO_SOURCE}")

# libtp_sshd_crypto.so is the name dartssh2's loader resolves by soname, and
# the name the Android Gradle Plugin places in the APK's lib/<abi>/.
set_target_properties(tp_sshd_crypto PROPERTIES OUTPUT_NAME "tp_sshd_crypto")

target_include_directories(tp_sshd_crypto PRIVATE "${TP_SSHD_CRYPTO_VENDOR}/include")
target_compile_options(tp_sshd_crypto PRIVATE -O2)

# Static libcrypto: the shim carries no runtime dependency of its own, so the
# APK needs no bundled libcrypto.so. (-ldl/-lz are the Android system libs the
# static build expects.)
target_link_libraries(tp_sshd_crypto
  "${TP_SSHD_CRYPTO_VENDOR}/lib/libcrypto.a"
  dl
  z
)
