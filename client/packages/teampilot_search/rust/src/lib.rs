use std::ffi::{c_char, CStr};

#[no_mangle]
pub extern "C" fn tp_search_version() -> *const c_char {
    c"teampilot_search/0.1.0".as_ptr()
}

// 其余符号在 Task 2 实现；这里先声明占位避免链接期/ffigen 缺符号。
#[no_mangle]
pub unsafe extern "C" fn tp_search_new(
    _config: *const std::ffi::c_void,
    _out: *mut std::ffi::c_void,
) -> i32 {
    -3
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_next(
    _handle: *mut std::ffi::c_void,
    _chunk: *mut std::ffi::c_void,
) -> i32 {
    -3
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_cancel(_handle: *mut std::ffi::c_void) {}

#[no_mangle]
pub unsafe extern "C" fn tp_search_free(_handle: *mut std::ffi::c_void) {}
