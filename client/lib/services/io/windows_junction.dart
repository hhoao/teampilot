import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Creates Windows directory junctions without spawning a process.
///
/// `cmd /c mklink /J` costs 100-200ms per link (a full cmd.exe cold start);
/// a session launch creates 20+ links, adding ~2.5s to connect. This uses
/// the same mechanism `mklink /J` itself uses: an empty directory plus a
/// mount-point reparse buffer set via `FSCTL_SET_REPARSE_POINT`.
///
/// Junctions are preferred over `dart:io` `Link.create` on Windows because
/// Dart symbolic links are flagged untrusted and fail directory traversal
/// with "untrusted mount point" (errno 448) in other processes.
abstract final class WindowsJunction {
  static const _fsctlSetReparsePoint = 0x000900A4;
  static const _ioReparseTagMountPoint = 0xA0000003;
  static const _genericWrite = 0x40000000;
  static const _openExisting = 3;
  static const _fileFlagOpenReparsePoint = 0x00200000;
  static const _fileFlagBackupSemantics = 0x02000000;
  static const _invalidHandle = -1;

  static final DynamicLibrary? _kernel32 = _tryOpenKernel32();

  static DynamicLibrary? _tryOpenKernel32() {
    try {
      return DynamicLibrary.open('kernel32.dll');
    } catch (_) {
      return null;
    }
  }

  static int Function(Pointer<Utf16>, Pointer<Void>)? _createDirectoryW;
  static int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)?
  _createFileW;
  static int Function(int, int, Pointer<Void>, int, Pointer<Void>, int,
      Pointer<Uint32>, Pointer<Void>)? _deviceIoControl;
  static int Function(int)? _closeHandle;

  /// Creates a junction at [linkPath] pointing at the absolute [target]
  /// directory. Returns false when [linkPath] already exists or the reparse
  /// write fails — callers fall back to `mklink /J`.
  static bool create({required String linkPath, required String target}) {
    if (!_resolveFunctions()) return false;
    final lp = linkPath.toNativeUtf16();
    final dirCreated = _createDirectoryW!(lp, nullptr) != 0;
    calloc.free(lp);
    if (!dirCreated) return false;

    final substitute = '\\??\\$target';
    final printName = target;
    final subUnits = substitute.codeUnits;
    final printUnits = printName.codeUnits;
    // Path buffer: substitute + NUL + print + NUL, lengths in bytes.
    final dataLength = 8 + (subUnits.length + 1 + printUnits.length + 1) * 2;
    final total = 8 + dataLength;
    final buf = calloc<Uint8>(total);
    try {
      buf.cast<Uint32>()[0] = _ioReparseTagMountPoint;
      buf[4] = dataLength & 0xFF;
      buf[5] = dataLength >> 8;
      final header = (buf.cast<Uint16>() + 4);
      header[0] = 0; // SubstituteNameOffset
      header[1] = subUnits.length * 2; // SubstituteNameLength
      header[2] = (subUnits.length + 1) * 2; // PrintNameOffset
      header[3] = printUnits.length * 2; // PrintNameLength
      final path = header + 4;
      var i = 0;
      for (final unit in subUnits) {
        path[i++] = unit;
      }
      path[i++] = 0;
      for (final unit in printUnits) {
        path[i++] = unit;
      }
      path[i++] = 0;

      final lpw = linkPath.toNativeUtf16();
      final handle = _createFileW!(
        lpw,
        _genericWrite,
        0,
        nullptr,
        _openExisting,
        _fileFlagOpenReparsePoint | _fileFlagBackupSemantics,
        0,
      );
      calloc.free(lpw);
      if (handle == _invalidHandle) return false;
      try {
        final returned = calloc<Uint32>();
        try {
          return _deviceIoControl!(
                handle,
                _fsctlSetReparsePoint,
                buf.cast(),
                total,
                nullptr,
                0,
                returned,
                nullptr,
              ) !=
              0;
        } finally {
          calloc.free(returned);
        }
      } finally {
        _closeHandle!(handle);
      }
    } finally {
      calloc.free(buf);
    }
  }

  static bool _resolveFunctions() {
    if (_createDirectoryW != null) return true;
    final kernel32 = _kernel32;
    if (kernel32 == null) return false;
    try {
      _createDirectoryW = kernel32.lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Void>),
        int Function(Pointer<Utf16>, Pointer<Void>)
      >('CreateDirectoryW');
      _createFileW = kernel32.lookupFunction<
        IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32,
            Uint32, IntPtr),
        int Function(
          Pointer<Utf16>,
          int,
          int,
          Pointer<Void>,
          int,
          int,
          int,
        )
      >('CreateFileW');
      _deviceIoControl = kernel32.lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32, Pointer<Void>,
            Uint32, Pointer<Uint32>, Pointer<Void>),
        int Function(
          int,
          int,
          Pointer<Void>,
          int,
          Pointer<Void>,
          int,
          Pointer<Uint32>,
          Pointer<Void>,
        )
      >('DeviceIoControl');
      _closeHandle = kernel32.lookupFunction<
        Int32 Function(IntPtr),
        int Function(int)
      >('CloseHandle');
      return true;
    } catch (_) {
      return false;
    }
  }
}
