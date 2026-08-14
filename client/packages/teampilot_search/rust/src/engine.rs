//! Search pipeline: worker thread walking the tree with `ignore` and
//! searching files with `grep-searcher`, feeding a bounded channel that
//! `tp_search_next` drains in chunks.

use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender, TrySendError};
use std::sync::Arc;
use std::thread;

use grep::matcher::Matcher;
use grep::regex::RegexMatcher;
use grep::searcher::sinks::UTF8;
use grep::searcher::{BinaryDetection, SearcherBuilder};
use ignore::overrides::OverrideBuilder;
use ignore::{WalkBuilder, WalkState};

/// Longest line we keep text for; longer lines emit a text-less match.
pub const MAX_LINE_BYTES: usize = 1024 * 1024;
const CHANNEL_CAPACITY: usize = 4096;
const CHANNEL_TICK: std::time::Duration = std::time::Duration::from_millis(5);

#[derive(Debug)]
pub enum SearchError {
    InvalidPattern,
    RootUnreadable,
    Internal(String),
}

pub struct SearchConfig {
    pub root: String,
    pub pattern: String,
    pub is_regex: bool,
    pub case_sensitive: bool,
    pub smart_case: bool,
    pub use_gitignore: bool,
    pub files_to_include: Vec<String>,
    pub files_to_exclude: Vec<String>,
    pub max_file_size: u64,
    pub max_results: u64,
    pub max_chunk_matches: usize,
    pub max_chunk_bytes: usize,
}

#[derive(Debug, Clone)]
pub struct SearchMatchData {
    pub path: String,
    pub relative_path: String,
    pub line_number: u64,
    pub line_text: String,
    pub match_start: usize,
    pub match_end: usize,
}

pub enum SearchMsg {
    Line(SearchMatchData),
    Done { truncated: bool },
}

pub struct TpSearchHandle {
    pub rx: Receiver<SearchMsg>,
    pub cancel: Arc<AtomicBool>,
    pub truncated: bool,
    pub finished: bool,
    pub pending: Vec<SearchMatchData>,
    pub max_chunk_matches: usize,
    pub max_chunk_bytes: usize,
}

fn has_uppercase(s: &str) -> bool {
    s.chars().any(|c| c.is_uppercase())
}

fn build_matcher(config: &SearchConfig) -> Result<RegexMatcher, SearchError> {
    let mut builder = grep::regex::RegexMatcherBuilder::new();
    if !config.case_sensitive {
        if config.smart_case && has_uppercase(&config.pattern) {
            // smart case: uppercase pattern means case-sensitive.
        } else {
            builder.case_insensitive(true);
        }
    }
    let pattern = if config.is_regex {
        config.pattern.clone()
    } else {
        regex_syntax::escape(&config.pattern)
    };
    builder.build(&pattern).map_err(|_| SearchError::InvalidPattern)
}

fn build_walker(config: &SearchConfig) -> Result<WalkBuilder, SearchError> {
    if !Path::new(&config.root).is_dir() {
        return Err(SearchError::RootUnreadable);
    }
    let mut wb = WalkBuilder::new(&config.root);
    wb.hidden(true)
        .ignore(config.use_gitignore)
        .git_ignore(config.use_gitignore)
        .git_global(false) // deterministic: no user-global gitignore
        .git_exclude(false)
        .require_git(false) // honor .gitignore even outside git repos (IDE semantics)
        .parents(true)
        .follow_links(false);

    let mut ob = OverrideBuilder::new(&config.root);
    for g in &config.files_to_include {
        ob.add(g).map_err(|e| SearchError::Internal(e.to_string()))?;
    }
    for g in &config.files_to_exclude {
        ob.add(&format!("!{g}"))
            .map_err(|e| SearchError::Internal(e.to_string()))?;
    }
    let overrides = ob
        .build()
        .map_err(|e| SearchError::Internal(e.to_string()))?;
    wb.overrides(overrides);
    Ok(wb)
}

enum SendOutcome {
    Sent,
    Disconnected,
    Cancelled,
}

fn send_with_cancel(
    tx: &SyncSender<SearchMsg>,
    msg: SearchMsg,
    cancel: &AtomicBool,
) -> SendOutcome {
    let mut msg = msg;
    loop {
        if cancel.load(Ordering::Relaxed) {
            return SendOutcome::Cancelled;
        }
        match tx.try_send(msg) {
            Ok(()) => return SendOutcome::Sent,
            Err(TrySendError::Full(m)) => {
                msg = m;
                thread::sleep(CHANNEL_TICK);
            }
            Err(TrySendError::Disconnected(_)) => return SendOutcome::Disconnected,
        }
    }
}

pub fn spawn_search(config: &SearchConfig) -> Result<TpSearchHandle, SearchError> {
    let matcher = Arc::new(build_matcher(config)?);
    let walker = build_walker(config)?;
    let root = config.root.clone();

    let cancel = Arc::new(AtomicBool::new(false));
    let stop = Arc::new(AtomicBool::new(false));
    let total = Arc::new(AtomicU64::new(0));
    let (tx, rx) = mpsc::sync_channel(CHANNEL_CAPACITY);

    let worker_cancel = cancel.clone();
    let worker_stop = stop.clone();
    let worker_total = total.clone();
    let worker_matcher = matcher.clone();
    let max_results = config.max_results;
    let max_file_size = config.max_file_size;

    thread::spawn(move || {
        walker.build_parallel().run(|| {
            let tx = tx.clone();
            let cancel = worker_cancel.clone();
            let stop = worker_stop.clone();
            let total = worker_total.clone();
            let matcher = worker_matcher.clone();
            let root = root.clone();
            Box::new(move |entry| {
                if cancel.load(Ordering::Relaxed) || stop.load(Ordering::Relaxed) {
                    return WalkState::Quit;
                }
                let entry = match entry {
                    Ok(e) => e,
                    Err(_) => return WalkState::Continue,
                };
                if !entry.file_type().map(|ft| ft.is_file()).unwrap_or(false) {
                    return WalkState::Continue;
                }
                let path = entry.path();
                if max_file_size > 0 {
                    if let Ok(md) = entry.metadata() {
                        if md.len() > max_file_size {
                            return WalkState::Continue;
                        }
                    }
                }
                let relative_path = path
                    .strip_prefix(&root)
                    .unwrap_or(path)
                    .to_string_lossy()
                    .into_owned();
                let path_str = path.to_string_lossy().into_owned();

                let mut searcher = SearcherBuilder::new()
                    .binary_detection(BinaryDetection::quit(b'\x00'))
                    .build();

                let _ = searcher.search_path(
                    matcher.as_ref(),
                    path,
                    UTF8(|lnum, line| {
                        if cancel.load(Ordering::Relaxed) || stop.load(Ordering::Relaxed) {
                            return Ok(false);
                        }
                        if line.len() > MAX_LINE_BYTES {
                            // Text-less placeholder: line number kept, offsets zeroed.
                            let count = total.fetch_add(1, Ordering::Relaxed) + 1;
                            let data = SearchMatchData {
                                path: path_str.clone(),
                                relative_path: relative_path.clone(),
                                line_number: lnum as u64,
                                line_text: String::new(),
                                match_start: 0,
                                match_end: 0,
                            };
                            match send_with_cancel(&tx, SearchMsg::Line(data), &cancel) {
                                SendOutcome::Cancelled | SendOutcome::Disconnected => {
                                    return Ok(false)
                                }
                                SendOutcome::Sent => {}
                            }
                            if max_results > 0 && count >= max_results {
                                stop.store(true, Ordering::Relaxed);
                                return Ok(false);
                            }
                            return Ok(true);
                        }
                        let _ = matcher.find_iter(line.as_bytes(), |m| {
                            let count = total.fetch_add(1, Ordering::Relaxed) + 1;
                            let data = SearchMatchData {
                                path: path_str.clone(),
                                relative_path: relative_path.clone(),
                                line_number: lnum as u64,
                                line_text: line.to_owned(),
                                match_start: m.start(),
                                match_end: m.end(),
                            };
                            match send_with_cancel(&tx, SearchMsg::Line(data), &cancel) {
                                SendOutcome::Cancelled | SendOutcome::Disconnected => return false,
                                SendOutcome::Sent => {}
                            }
                            if max_results > 0 && count >= max_results {
                                stop.store(true, Ordering::Relaxed);
                                return false;
                            }
                            true
                        });
                        Ok(true)
                    }),
                );
                WalkState::Continue
            })
        });
        let truncated = stop.load(Ordering::Relaxed);
        let _ = tx.send(SearchMsg::Done {
            truncated,
        });
    });

    Ok(TpSearchHandle {
        rx,
        cancel,
        truncated: false,
        finished: false,
        pending: Vec::new(),
        max_chunk_matches: config.max_chunk_matches,
        max_chunk_bytes: config.max_chunk_bytes,
    })
}
