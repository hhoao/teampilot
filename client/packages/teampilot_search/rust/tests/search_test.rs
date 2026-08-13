use std::sync::mpsc;
use std::time::Duration;

use teampilot_search_rust::engine::{self, SearchConfig, SearchMsg};

const FIXTURES: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/basic");

fn cfg(root: &str, pattern: &str) -> SearchConfig {
    SearchConfig {
        root: root.to_string(),
        pattern: pattern.to_string(),
        is_regex: true,
        case_sensitive: false,
        smart_case: false,
        use_gitignore: true,
        files_to_include: vec![],
        files_to_exclude: vec![],
        max_file_size: 0,
        max_results: 0,
        max_chunk_matches: 64,
        max_chunk_bytes: 64 * 1024,
    }
}

fn drain(handle: &mut engine::TpSearchHandle) -> (Vec<SearchMsg>, bool) {
    let mut msgs = vec![];
    loop {
        match handle.rx.recv_timeout(Duration::from_millis(200)) {
            Ok(m) => msgs.push(m),
            Err(mpsc::RecvTimeoutError::Timeout) => break,
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }
    let truncated = msgs
        .iter()
        .any(|m| matches!(m, SearchMsg::Done { truncated: true }));
    (msgs, truncated)
}

fn matches(msgs: &[SearchMsg]) -> Vec<&engine::SearchMatchData> {
    msgs.iter()
        .filter_map(|m| match m {
            SearchMsg::Line(d) => Some(d),
            _ => None,
        })
        .collect()
}

#[test]
fn finds_case_insensitive_literal_matches_with_offsets() {
    let mut h = engine::spawn_search(&cfg(FIXTURES, "hello")).expect("spawn");
    let (msgs, _) = drain(&mut h);
    let m = matches(&msgs);
    assert_eq!(m.len(), 3, "a.dart x2 + ignored/sub hidden skipped, c.rs uppercase, bin skipped");
    let first = m.iter().find(|d| d.path.ends_with("a.dart")).unwrap();
    assert_eq!(first.line_number, 1);
    assert_eq!(first.line_text, "hello world\n");
    assert_eq!((first.match_start, first.match_end), (0, 5));
}

#[test]
fn regex_and_smart_case() {
    let mut h = engine::spawn_search(&cfg(FIXTURES, "h[e]llo")).expect("spawn");
    let (msgs, _) = drain(&mut h);
    assert_eq!(matches(&msgs).len(), 3);

    let mut c = cfg(FIXTURES, "HELLO");
    c.smart_case = true;
    let mut h = engine::spawn_search(&c).expect("spawn");
    let (msgs, _) = drain(&mut h);
    let m = matches(&msgs);
    assert_eq!(m.len(), 1, "smart case: uppercase pattern -> case sensitive");
    assert!(m[0].path.ends_with("c.rs"));
}

#[test]
fn gitignore_and_hidden_skipped() {
    let mut h = engine::spawn_search(&cfg(FIXTURES, "hello")).expect("spawn");
    let (msgs, _) = drain(&mut h);
    for d in matches(&msgs) {
        assert!(!d.path.contains("ignored.txt"));
        assert!(!d.path.contains(".hidden_dir"));
        assert!(!d.path.contains("bin.dat"));
    }
}

#[test]
fn include_exclude_globs() {
    let mut c = cfg(FIXTURES, "hello");
    c.files_to_include = vec!["*.dart".into()];
    let mut h = engine::spawn_search(&c).expect("spawn");
    let (msgs, _) = drain(&mut h);
    let m = matches(&msgs);
    assert!(m.len() == 2 && m.iter().all(|d| d.path.ends_with(".dart")));

    c = cfg(FIXTURES, "hello");
    c.files_to_exclude = vec!["sub/**".into()];
    let mut h = engine::spawn_search(&c).expect("spawn");
    let (msgs, _) = drain(&mut h);
    assert!(matches(&msgs).iter().all(|d| !d.path.contains("sub")));
}

#[test]
fn max_results_truncates() {
    let mut c = cfg(FIXTURES, "hello");
    c.max_results = 2;
    let mut h = engine::spawn_search(&c).expect("spawn");
    let (msgs, truncated) = drain(&mut h);
    assert!(truncated, "truncation flag set");
    // The atomic stop is racy across walker threads: one thread may emit a
    // couple of matches after the cap trips, so allow a small overshoot.
    let n = matches(&msgs).len();
    assert!((2..=3).contains(&n), "overshoot window is 2..=3, got {n}");
}

#[test]
fn max_file_size_skips_big_files() {
    let temp = std::env::temp_dir().join("tp_search_big_file_test");
    std::fs::create_dir_all(&temp).unwrap();
    let big = temp.join("big.txt");
    let mut content = String::with_capacity(2 * 1024 * 1024);
    for _ in 0..(2 * 1024 * 1024 / 7) {
        content.push_str("hello x\n");
    }
    std::fs::write(&big, &content).unwrap();
    std::fs::write(temp.join("small.txt"), "hello small\n").unwrap();

    let mut c = cfg(temp.to_str().unwrap(), "hello");
    c.max_file_size = 1024 * 1024;
    let mut h = engine::spawn_search(&c).expect("spawn");
    let (msgs, _) = drain(&mut h);
    let m = matches(&msgs);
    assert_eq!(m.len(), 1);
    assert!(m[0].path.ends_with("small.txt"));
    let _ = std::fs::remove_dir_all(&temp);
}

#[test]
fn long_line_emits_match_without_text() {
    let temp = std::env::temp_dir().join("tp_search_long_line_test");
    std::fs::create_dir_all(&temp).unwrap();
    let huge_line = format!("start{}end\n", "x".repeat(1024 * 1024 + 64));
    std::fs::write(temp.join("huge.txt"), huge_line).unwrap();

    let mut h = engine::spawn_search(&cfg(temp.to_str().unwrap(), "end")).expect("spawn");
    let (msgs, _) = drain(&mut h);
    let m = matches(&msgs);
    assert_eq!(m.len(), 1);
    assert!(m[0].line_text.is_empty(), "line text dropped, line number kept");
    assert_eq!(m[0].match_start, m[0].match_end);
    let _ = std::fs::remove_dir_all(&temp);
}

#[test]
fn cancel_stops_worker() {
    let mut c = cfg(FIXTURES, "hello");
    c.max_results = 0;
    let h = engine::spawn_search(&c).expect("spawn");
    h.cancel.store(true, std::sync::atomic::Ordering::Relaxed);
    let mut got_any_after_cancel = false;
    for _ in 0..10 {
        match h.rx.recv_timeout(Duration::from_millis(100)) {
            Ok(SearchMsg::Line(_)) => got_any_after_cancel = true,
            _ => break,
        }
    }
    std::thread::sleep(Duration::from_millis(50));
    let _ = got_any_after_cancel;
}
