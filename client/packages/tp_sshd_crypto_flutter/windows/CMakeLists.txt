# The Flutter tooling requires a Visual Studio with CMake 3.14 or later.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "tp_sshd_crypto_flutter")
project(${PROJECT_NAME} LANGUAGES C)

# The shim source, compiled from the dartssh2 package's copy — this package
# holds no C of its own (see README.md). tp_sshd_crypto.dll (no lib prefix) is
# the file name dartssh2's loader resolves by soname, so the target's output
# name is part of the contract: do not rename it.
# Path resolution: like the Linux lane, resolve the symlink the Flutter tool
# builds this plugin through before walking to the sibling package — otherwise
# the walk lands inside `windows/flutter/ephemeral/.plugin_symlinks/`, where
# the `dartssh2` sibling does not exist (it is a plain Dart path dependency,
# not a plugin).
get_filename_component(_tp_sshd_crypto_pkg_dir
  "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH
)
set(TP_SSHD_CRYPTO_SOURCE
  "${_tp_sshd_crypto_pkg_dir}/../dartssh2/native/tp_sshd_crypto.c"
)
if(NOT EXISTS "${TP_SSHD_CRYPTO_SOURCE}")
  message(FATAL_ERROR
    "tp_sshd_crypto_flutter: the dartssh2 shim source is missing at "
    "${TP_SSHD_CRYPTO_SOURCE}. The plugin compiles that file rather than "
    "shipping its own copy; check that the dartssh2 path dependency is "
    "checked out."
  )
endif()

add_library(tp_sshd_crypto SHARED "${TP_SSHD_CRYPTO_SOURCE}")

set_target_properties(tp_sshd_crypto PROPERTIES
  OUTPUT_NAME "tp_sshd_crypto"
)

# -O2 to match the Linux lane and native/build.sh's local build; the shim is a
# thin translation layer over libcrypto, so there is nothing to gain from /Ox.
target_compile_options(tp_sshd_crypto PRIVATE $<$<NOT:$<CONFIG:Debug>>:-O2>)

# Windows ships no libcrypto an app may link against, so unlike the Linux lane
# OpenSSL has to come from the build environment: vcpkg, with the x64-windows
# static triplet (native/prebuilt/README.md builds the windows/x64 prebuilt
# that way, precisely so the shipped DLL carries no libcrypto dependency). A
# `flutter build windows` without vcpkg's OpenSSL fails here — that is the
# documented assumption of this lane, not a wiring bug.
# Prefer the static lib. FindOpenSSL only pulls Winsock and Crypt32 when this
# is a CMake variable; an environment variable is not enough, and the static
# libcrypto then fails to link those Windows imports.
set(OPENSSL_USE_STATIC_LIBS TRUE)
find_package(OpenSSL REQUIRED)
target_link_libraries(tp_sshd_crypto PRIVATE OpenSSL::Crypto ws2_32 crypt32)

set(tp_sshd_crypto_flutter_bundled_libraries
  $<TARGET_FILE:tp_sshd_crypto>
  PARENT_SCOPE
)
