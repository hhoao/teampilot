pub mod engine;
pub mod file_index;
pub mod fuzzy;

use std::ffi::{c_char, CStr};
use std::slice;
use std::sync::atomic::Ordering;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

pub use engine::{SearchConfig, SearchError, SearchMatchData, SearchMsg, TpSearchHandle};

use engine::spawn_search;
use file_index::{FileIndex, FileIndexConfig, FileIndexError, FileMatchMode};

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

unsafe fn read_string_array(ptr: *const *const c_char, count: u32) -> Result<Vec<String>, String> {
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
            let pending_bytes: usize = h
                .pending
                .iter()
                .map(|d| d.line_text.len() + d.path.len())
                .sum();
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

pub struct TpFileIndexHandle {
    index: Arc<Mutex<FileIndex>>,
    cancel: Arc<std::sync::atomic::AtomicBool>,
    build_state: Mutex<FileIndexBuildState>,
}

enum FileIndexBuildState {
    Idle,
    Running(JoinHandle<i32>),
    Completed(i32),
}

#[repr(C)]
pub struct TpFileIndexConfig {
    root: *const c_char,
    use_gitignore: i32,
    max_entries: u64,
    max_chunk_matches: u32,
    max_chunk_bytes: u32,
}

#[repr(C)]
pub struct TpFileIndexEntry {
    path: *const c_char,
    relative_path: *const c_char,
    name: *const c_char,
}

#[repr(C)]
pub struct TpFileIndexChunk {
    string_buf: *mut c_char,
    string_buf_cap: u32,
    string_buf_len: u32,
    entries: *mut TpFileIndexEntry,
    entries_cap: u32,
    entries_len: u32,
    truncated: i32,
}

fn map_file_index_error(error: FileIndexError) -> i32 {
    match error {
        FileIndexError::RootUnreadable => ERR_ROOT_UNREADABLE,
        FileIndexError::Internal(_) => ERR_INTERNAL,
    }
}

unsafe fn fill_file_index_chunk(
    chunk: &mut TpFileIndexChunk,
    entries: impl IntoIterator<Item = (String, String, String)>,
    truncated: bool,
) {
    chunk.string_buf_len = 0;
    chunk.entries_len = 0;
    chunk.truncated = if truncated { 1 } else { 0 };

    let str_cap = chunk.string_buf_cap as usize;
    let str_buf = if chunk.string_buf.is_null() {
        &mut []
    } else {
        std::slice::from_raw_parts_mut(chunk.string_buf as *mut u8, str_cap)
    };
    let entry_cap = chunk.entries_cap as usize;
    let entry_arr = if chunk.entries.is_null() {
        &mut []
    } else {
        std::slice::from_raw_parts_mut(chunk.entries, entry_cap)
    };

    let mut str_off = 0usize;
    let mut entry_idx = 0usize;
    let mut chunk_truncated = truncated;
    for (path, relative_path, name) in entries {
        if entry_idx >= entry_arr.len() {
            chunk_truncated = true;
            break;
        }
        let required = path.len() + relative_path.len() + name.len() + 3;
        if required > str_cap {
            chunk_truncated = true;
            continue;
        }
        if required > str_cap.saturating_sub(str_off) {
            chunk_truncated = true;
            break;
        }

        let path_off = str_off;
        str_off = match write_string(str_buf, str_off, &path) {
            Ok(offset) => offset,
            Err(_) => {
                chunk_truncated = true;
                break;
            }
        };
        let relative_path_off = str_off;
        str_off = match write_string(str_buf, str_off, &relative_path) {
            Ok(offset) => offset,
            Err(_) => {
                chunk_truncated = true;
                break;
            }
        };
        let name_off = str_off;
        str_off = match write_string(str_buf, str_off, &name) {
            Ok(offset) => offset,
            Err(_) => {
                chunk_truncated = true;
                break;
            }
        };
        let base = chunk.string_buf as usize;
        entry_arr[entry_idx] = TpFileIndexEntry {
            path: (base + path_off) as *const c_char,
            relative_path: (base + relative_path_off) as *const c_char,
            name: (base + name_off) as *const c_char,
        };
        entry_idx += 1;
    }
    chunk.string_buf_len = str_off as u32;
    chunk.entries_len = entry_idx as u32;
    chunk.truncated = if chunk_truncated { 1 } else { 0 };
}

#[no_mangle]
pub unsafe extern "C" fn tp_file_index_new(
    config: *const TpFileIndexConfig,
    out: *mut *mut TpFileIndexHandle,
) -> i32 {
    if config.is_null() || out.is_null() {
        return ERR_INTERNAL;
    }
    let cfg = &*config;
    let root = match read_string(cfg.root) {
        Ok(root) => root,
        Err(_) => return ERR_INTERNAL,
    };
    // Chunk limits are supplied by the caller's TpFileIndexChunk for now.
    match FileIndex::new(FileIndexConfig {
        root,
        use_gitignore: cfg.use_gitignore != 0,
        max_entries: cfg.max_entries,
    }) {
        Ok(index) => {
            let cancel = index.cancel_token();
            *out = Box::into_raw(Box::new(TpFileIndexHandle {
                index: Arc::new(Mutex::new(index)),
                cancel,
                build_state: Mutex::new(FileIndexBuildState::Idle),
            }));
            0
        }
        Err(error) => map_file_index_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn tp_file_index_build(handle: *mut TpFileIndexHandle) -> i32 {
    if handle.is_null() {
        return ERR_INTERNAL;
    }
    let handle = &*handle;
    match handle.index.lock() {
        Ok(mut index) => match index.build() {
            Ok(()) => 0,
            Err(error) => map_file_index_error(error),
        },
        Err(_) => ERR_INTERNAL,
    }
}

#[no_mangle]
pub unsafe extern "C" fn tp_file_index_build_start(handle: *mut TpFileIndexHandle) -> i32 {
    if handle.is_null() {
        return ERR_INTERNAL;
    }
    let handle = &*handle;
    let mut build_state = match handle.build_state.lock() {
        Ok(build_state) => build_state,
        Err(_) => return ERR_INTERNAL,
    };
    if !matches!(*build_state, FileIndexBuildState::Idle) {
        return ERR_INTERNAL;
    }
    let index = handle.index.clone();
    *build_state = FileIndexBuildState::Running(std::thread::spawn(move || match index.lock() {
        Ok(mut index) => match index.build() {
            Ok(()) => 0,
            Err(error) => map_file_index_error(error),
        },
        Err(_) => ERR_INTERNAL,
    }));
    0
}

#[no_mangle]
pub unsafe extern "C" fn tp_file_index_build_poll(handle: *mut TpFileIndexHandle) -> i32 {
    if handle.is_null() {
        return ERR_INTERNAL;
    }
    let handle = &*handle;
    let mut build_state = match handle.build_state.lock() {
        Ok(build_state) => build_state,
        Err(_) => return ERR_INTERNAL,
    };
    let completed = match &*build_state {
        FileIndexBuildState::Idle => return ERR_INTERNAL,
        FileIndexBuildState::Completed(status) => return if *status == 0 { 1 } else { *status },
        FileIndexBuildState::Running(thread) if !thread.is_finished() => return 0,
        FileIndexBuildState::Running(_) => {
            match std::mem::replace(&mut *build_state, FileIndexBuildState::Idle) {
                FileIndexBuildState::Running(thread) => thread.join().unwrap_or(ERR_INTERNAL),
                _ => unreachable!(),
            }
        }
    };
    *build_state = FileIndexBuildState::Completed(completed);
    if completed == 0 {
        1
    } else {
        completed
    }
}

#[no_mangle]
pub unsafe extern "C" fn tp_file_index_cancel(handle: *mut TpFileIndexHandle) {
    if !handle.is_null() {
        (*handle).cancel.store(true, Ordering::Relaxed);
    }
}

#[no_mangle]
pub unsafe extern "C" fn tp_file_index_query(
    handle: *mut TpFileIndexHandle,
    query: *const c_char,
    mode: i32,
    limit: u32,
    chunk: *mut TpFileIndexChunk,
) -> i32 {
    if handle.is_null() || chunk.is_null() {
        return ERR_INTERNAL;
    }
    let query = match read_string(query) {
        Ok(query) => query,
        Err(_) => return ERR_INTERNAL,
    };
    let mode = match mode {
        0 => FileMatchMode::Fuzzy,
        1 => FileMatchMode::Contains,
        _ => return ERR_INTERNAL,
    };
    let handle = &*handle;
    let index = match handle.index.lock() {
        Ok(index) => index,
        Err(_) => return ERR_INTERNAL,
    };
    let hits = index.query(&query, mode, limit as usize);
    fill_file_index_chunk(
        &mut *chunk,
        hits.into_iter()
            .map(|hit| (hit.path, hit.relative_path, hit.name)),
        index.truncated(),
    );
    0
}

#[no_mangle]
pub unsafe extern "C" fn tp_file_index_query_dirs(
    handle: *mut TpFileIndexHandle,
    query: *const c_char,
    limit: u32,
    chunk: *mut TpFileIndexChunk,
) -> i32 {
    if handle.is_null() || chunk.is_null() {
        return ERR_INTERNAL;
    }
    let query = match read_string(query) {
        Ok(query) => query,
        Err(_) => return ERR_INTERNAL,
    };
    let handle = &*handle;
    let index = match handle.index.lock() {
        Ok(index) => index,
        Err(_) => return ERR_INTERNAL,
    };
    let directories = index.query_dirs(&query, limit as usize);
    fill_file_index_chunk(
        &mut *chunk,
        directories
            .into_iter()
            .map(|relative_path| (String::new(), relative_path, String::new())),
        index.truncated(),
    );
    0
}

#[no_mangle]
pub unsafe extern "C" fn tp_file_index_free(handle: *mut TpFileIndexHandle) {
    if !handle.is_null() {
        let handle = Box::from_raw(handle);
        handle.cancel.store(true, Ordering::Relaxed);
        drop(handle);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::{CStr, CString};
    use std::path::PathBuf;
    use std::ptr;

    fn fixture_root() -> CString {
        CString::new(
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("tests/fixtures/file_index")
                .to_string_lossy()
                .into_owned(),
        )
        .unwrap()
    }

    #[test]
    fn file_index_ffi_writes_file_and_directory_entries() {
        let root = fixture_root();
        let config = TpFileIndexConfig {
            root: root.as_ptr(),
            use_gitignore: 1,
            max_entries: 100,
            max_chunk_matches: 0,
            max_chunk_bytes: 0,
        };
        let mut handle = ptr::null_mut();
        assert_eq!(unsafe { tp_file_index_new(&config, &mut handle) }, 0);
        assert_eq!(unsafe { tp_file_index_build_start(handle) }, 0);
        loop {
            match unsafe { tp_file_index_build_poll(handle) } {
                0 => std::thread::yield_now(),
                1 => break,
                status => panic!("file index build failed with code {status}"),
            }
        }

        let query = CString::new("router").unwrap();
        let mut string_buf = vec![0i8; 1024];
        let mut entries = Vec::<TpFileIndexEntry>::with_capacity(4);
        let mut chunk = TpFileIndexChunk {
            string_buf: string_buf.as_mut_ptr(),
            string_buf_cap: string_buf.len() as u32,
            string_buf_len: 0,
            entries: entries.as_mut_ptr(),
            entries_cap: entries.capacity() as u32,
            entries_len: 0,
            truncated: 0,
        };
        assert_eq!(
            unsafe { tp_file_index_query(handle, query.as_ptr(), 1, 10, &mut chunk) },
            0
        );
        assert_eq!(chunk.entries_len, 1);
        let entry = unsafe { &*chunk.entries };
        assert_eq!(
            unsafe { CStr::from_ptr(entry.relative_path) }
                .to_str()
                .unwrap(),
            "lib/app_router.dart"
        );
        assert_eq!(
            unsafe { CStr::from_ptr(entry.name) }.to_str().unwrap(),
            "app_router.dart"
        );

        let dir_query = CString::new("li").unwrap();
        assert_eq!(
            unsafe { tp_file_index_query_dirs(handle, dir_query.as_ptr(), 10, &mut chunk) },
            0
        );
        assert_eq!(chunk.entries_len, 1);
        assert_eq!(
            unsafe { CStr::from_ptr((*chunk.entries).relative_path) }
                .to_str()
                .unwrap(),
            "lib"
        );
        assert_eq!(
            unsafe { CStr::from_ptr((*chunk.entries).path) }
                .to_str()
                .unwrap(),
            ""
        );
        assert_eq!(
            unsafe { CStr::from_ptr((*chunk.entries).name) }
                .to_str()
                .unwrap(),
            ""
        );

        unsafe { tp_file_index_free(handle) };
    }

    #[test]
    fn file_index_chunk_marks_truncated_when_entry_capacity_clips_results() {
        let mut string_buf = vec![0i8; 64];
        let mut entries = Vec::<TpFileIndexEntry>::with_capacity(1);
        let mut chunk = TpFileIndexChunk {
            string_buf: string_buf.as_mut_ptr(),
            string_buf_cap: string_buf.len() as u32,
            string_buf_len: 0,
            entries: entries.as_mut_ptr(),
            entries_cap: entries.capacity() as u32,
            entries_len: 0,
            truncated: 0,
        };

        unsafe {
            fill_file_index_chunk(
                &mut chunk,
                [
                    ("a".to_string(), "a".to_string(), "a".to_string()),
                    ("b".to_string(), "b".to_string(), "b".to_string()),
                ],
                false,
            );
        }

        assert_eq!(chunk.entries_len, 1);
        assert_eq!(chunk.truncated, 1);
    }

    #[test]
    fn file_index_chunk_marks_truncated_when_string_buffer_clips_results() {
        let mut string_buf = vec![0i8; 6];
        let mut entries = Vec::<TpFileIndexEntry>::with_capacity(2);
        let mut chunk = TpFileIndexChunk {
            string_buf: string_buf.as_mut_ptr(),
            string_buf_cap: string_buf.len() as u32,
            string_buf_len: 0,
            entries: entries.as_mut_ptr(),
            entries_cap: entries.capacity() as u32,
            entries_len: 0,
            truncated: 0,
        };

        unsafe {
            fill_file_index_chunk(
                &mut chunk,
                [
                    ("a".to_string(), "".to_string(), "".to_string()),
                    ("b".to_string(), "".to_string(), "".to_string()),
                ],
                false,
            );
        }

        assert_eq!(chunk.entries_len, 1);
        assert_eq!(chunk.truncated, 1);
    }
}
