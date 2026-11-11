# The Flutter tooling requires CMake 3.10 or later. Do not raise this, or the
# plugin stops compiling for some consumers.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "tp_sshd_crypto_flutter")
project(${PROJECT_NAME} LANGUAGES C)

# The shim source, compiled from the dartssh2 package's copy — this package
# holds no C of its own (see README.md). libtp_sshd_crypto.so is the file name
# dartssh2's loader resolves by soname, so the target's output name is part of
# the contract: do not rename it.
#
# Path resolution: the Flutter tool does not build this plugin in place — it
# symlinks the package into the app's `linux/flutter/ephemeral/.plugin_symlinks/`
# and builds from there, so a relative walk from CMAKE_CURRENT_SOURCE_DIR lands
# inside that directory, where the `dartssh2` sibling does not exist (it is a
# plain Dart path dependency, not a plugin). Resolving the symlink back to the
# real package directory first makes the sibling walk correct in both
# configurations (in-place and symlinked).
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

# -O2 to match native/build.sh's local build; the shim is a thin translation
# layer over libcrypto, so there is nothing to gain from -O3.
target_compile_options(tp_sshd_crypto PRIVATE -O2)

# The shim's Poly1305 is its own C, but every other operation goes through
# OpenSSL's EVP API (native/prebuilt/README.md documents the link policy per
# lane). Linux links the host's libcrypto, so the resulting bundle needs
# OpenSSL 3 at load time — a dlopen failure naming libcrypto.so.3 is that
# dependency missing, not the shim being absent.
target_link_libraries(tp_sshd_crypto PRIVATE crypto)

# The app's linux/CMakeLists.txt installs every PLUGIN_BUNDLED_LIBRARIES entry
# into the bundle's lib/ directory, which is the location the loader's soname
# lookup resolves against. Naming this variable
# "<plugin package name>_bundled_libraries" is how generated_plugins.cmake
# collects it.
set(tp_sshd_crypto_flutter_bundled_libraries
  $<TARGET_FILE:tp_sshd_crypto>
  PARENT_SCOPE
)
