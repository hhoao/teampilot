pub mod engine;
pub mod file_index;
pub mod fuzzy;

use std::ffi::{c_char, CStr};
use std::slice;
use std::sync::atomic::Ordering;
use std::sync::mpsc;

pub use engine::{SearchConfig, SearchError, SearchMatchData, SearchMsg, TpSearchHandle};

use engine::spawn_search;

#[repr(C)]
pub struct TpSearchConfig {
    root: *const c_char,
    pattern: *const c_char,
    is_regex: i32,
    case_sensitive: i32,
    smart_case: i32,
    use_gitignore: i32,
    files_to_include: *const *const c_char,
    files_to_include_count: u32,
    files_to_exclude: *const *const c_char,
    files_to_exclude_count: u32,
    max_file_size: u64,
    max_results: u64,
    max_chunk_matches: u32,
    max_chunk_bytes: u32,
}

#[repr(C)]
pub struct TpSearchMatch {
    path: *const c_char,
    relative_path: *const c_char,
    line_number: u64,
    line_text: *const c_char,
    match_start: u32,
    match_end: u32,
}

#[repr(C)]
pub struct TpSearchChunk {
    string_buf: *mut c_char,
    string_buf_cap: u32,
    string_buf_len: u32,
    matches: *mut TpSearchMatch,
    matches_cap: u32,
    matches_len: u32,
    truncated: i32,
}

const ERR_INVALID_PATTERN: i32 = -1;
const ERR_ROOT_UNREADABLE: i32 = -2;
const ERR_INTERNAL: i32 = -3;

unsafe fn read_string(ptr: *const c_char) -> Result<String, String> {
    if ptr.is_null() {
        return Err("null string pointer".into());
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map(str::to_owned)
        .map_err(|e| e.to_string())
}

unsafe fn read_string_array(
    ptr: *const *const c_char,
    count: u32,
) -> Result<Vec<String>, String> {
    if ptr.is_null() {
        return Ok(Vec::new());
    }
    let items = slice::from_raw_parts(ptr, count as usize);
    items.iter().map(|p| read_string(*p)).collect()
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_version() -> *const c_char {
    c"teampilot_search/0.1.0".as_ptr()
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_new(
    config: *const TpSearchConfig,
    out: *mut *mut TpSearchHandle,
) -> i32 {
    if config.is_null() || out.is_null() {
        return ERR_INTERNAL;
    }
    let cfg = unsafe { &*config };
    let parsed = match (|| -> Result<SearchConfig, String> {
        Ok(SearchConfig {
            root: read_string(cfg.root)?,
            pattern: read_string(cfg.pattern)?,
            is_regex: cfg.is_regex != 0,
            case_sensitive: cfg.case_sensitive != 0,
            smart_case: cfg.smart_case != 0,
            use_gitignore: cfg.use_gitignore != 0,
            files_to_include: read_string_array(cfg.files_to_include, cfg.files_to_include_count)?,
            files_to_exclude: read_string_array(cfg.files_to_exclude, cfg.files_to_exclude_count)?,
            max_file_size: cfg.max_file_size,
            max_results: cfg.max_results,
            max_chunk_matches: cfg.max_chunk_matches.max(1) as usize,
            max_chunk_bytes: cfg.max_chunk_bytes.max(1024) as usize,
        })
    })() {
        Ok(c) => c,
        Err(_) => return ERR_INTERNAL,
    };
    match spawn_search(&parsed) {
        Ok(handle) => {
            *out = Box::into_raw(Box::new(handle));
            0
        }
        Err(SearchError::InvalidPattern) => ERR_INVALID_PATTERN,
        Err(SearchError::RootUnreadable) => ERR_ROOT_UNREADABLE,
        Err(SearchError::Internal(_)) => ERR_INTERNAL,
    }
}

fn write_string(buf: &mut [u8], offset: usize, s: &str) -> Result<usize, ()> {
    let bytes = s.as_bytes();
    let end = offset + bytes.len() + 1;
    if end > buf.len() {
        return Err(());
    }
    buf[offset..offset + bytes.len()].copy_from_slice(bytes);
    buf[offset + bytes.len()] = 0;
    Ok(end)
}

unsafe fn fill_chunk(h: &mut TpSearchHandle, chunk: &mut TpSearchChunk) {
    chunk.string_buf_len = 0;
    chunk.matches_len = 0;
    chunk.truncated = if h.truncated { 1 } else { 0 };

    let str_cap = chunk.string_buf_cap as usize;
    let str_buf = if chunk.string_buf.is_null() {
        &mut []
    } else {
        std::slice::from_raw_parts_mut(chunk.string_buf as *mut u8, str_cap)
    };
    let m_cap = chunk.matches_cap as usize;
    let m_arr = if chunk.matches.is_null() {
        &mut []
    } else {
        std::slice::from_raw_parts_mut(chunk.matches, m_cap)
    };

    let mut str_off = 0usize;
    let mut m_idx = 0usize;
    while m_idx < m_arr.len() && !h.pending.is_empty() {
        let d = &h.pending[0];
        let path_len = d.path.as_bytes().len() + 1;
        let rel_len = d.relative_path.as_bytes().len() + 1;
        let text_len = d.line_text.as_bytes().len() + 1;
        let remaining = str_cap.saturating_sub(str_off);

        // Pathological case: the paths alone exceed a fresh buffer, so this
        // match can never be serialized. Drop it instead of stalling.
        if path_len + rel_len > str_cap {
            h.pending.remove(0);
            continue;
        }
        // The head fits in a fresh buffer but not in the current remainder:
        // the buffer is genuinely full, leave it pending for the next call.
        if path_len + rel_len > remaining {
            break;
        }

        let path_off = str_off;
        str_off = match write_string(str_buf, str_off, &d.path) {
            Ok(o) => o,
            Err(_) => break,
        };
        let rel_off = str_off;
        str_off = match write_string(str_buf, str_off, &d.relative_path) {
            Ok(o) => o,
            Err(_) => break,
        };
        let text_off = str_off;
        let text_remaining = str_cap - str_off;
        let (match_start, match_end) = if text_len <= text_remaining {
            str_off = match write_string(str_buf, str_off, &d.line_text) {
                Ok(o) => o,
                Err(_) => break,
            };
            (d.match_start as u32, d.match_end as u32)
        } else {
            // The line text does not fit in the chunk buffer: emit a
            // text-less placeholder (empty line_text, zeroed offsets) so
            // the match is still reported and the head stays drainable.
            // With no byte left, the NUL terminating relative_path already
            // reads as an empty string.
            if text_remaining > 0 {
                str_buf[str_off] = 0;
                str_off += 1;
            }
            (0, 0)
        };
        let base = chunk.string_buf as usize;
        m_arr[m_idx] = TpSearchMatch {
            path: (base + path_off) as *const c_char,
            relative_path: (base + rel_off) as *const c_char,
            line_number: d.line_number,
            line_text: (base + text_off) as *const c_char,
            match_start,
            match_end,
        };
        m_idx += 1;
        h.pending.remove(0);
    }
    chunk.string_buf_len = str_off as u32;
    chunk.matches_len = m_idx as u32;
    if h.finished {
        chunk.truncated = if h.truncated { 1 } else { 0 };
    }
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_next(
    handle: *mut TpSearchHandle,
    chunk: *mut TpSearchChunk,
) -> i32 {
    if handle.is_null() || chunk.is_null() {
        return ERR_INTERNAL;
    }
    let h = &mut *handle;
    let c = &mut *chunk;

    if !h.finished && h.pending.len() < h.max_chunk_matches {
        let mut budget = h.max_chunk_matches.saturating_sub(h.pending.len());
        while budget > 0 {
            let pending_bytes: usize =
                h.pending.iter().map(|d| d.line_text.len() + d.path.len()).sum();
            if pending_bytes >= h.max_chunk_bytes {
                break;
            }
            match h.rx.recv_timeout(std::time::Duration::from_millis(5)) {
                Ok(SearchMsg::Line(d)) => {
                    h.pending.push(d);
                    budget -= 1;
                }
                Ok(SearchMsg::Done { truncated }) => {
                    h.truncated = truncated;
                    h.finished = true;
                    break;
                }
                Err(mpsc::RecvTimeoutError::Timeout) => break,
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    h.finished = true;
                    break;
                }
            }
        }
    }

    fill_chunk(h, c);

    if h.cancel.load(Ordering::Relaxed) {
        return 2;
    }
    if h.finished && h.pending.is_empty() {
        return 1;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_cancel(handle: *mut TpSearchHandle) {
    if !handle.is_null() {
        (*handle).cancel.store(true, Ordering::Relaxed);
    }
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_free(handle: *mut TpSearchHandle) {
    if handle.is_null() {
        return;
    }
    let h = Box::from_raw(handle);
    h.cancel.store(true, Ordering::Relaxed);
    drop(h);
}
