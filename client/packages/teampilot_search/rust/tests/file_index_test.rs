use std::path::PathBuf;

use teampilot_search_rust::file_index::{FileIndex, FileIndexConfig, FileMatchMode};

fn fixture_root() -> String {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/file_index")
        .to_string_lossy()
        .into_owned()
}

fn index(max_entries: u64) -> FileIndex {
    FileIndex::new(FileIndexConfig {
        root: fixture_root(),
        use_gitignore: true,
        max_entries,
    })
    .expect("fixture root should be readable")
}

#[test]
fn build_respects_gitignore_and_hidden() {
    let mut index = index(100);
    index.build().expect("index should build");

    assert_eq!(index.file_count(), 2);
    let paths: Vec<_> = index
        .query("", FileMatchMode::Contains, 10)
        .into_iter()
        .map(|hit| hit.relative_path)
        .collect();
    assert_eq!(paths, ["lib/app_router.dart", "lib/chat_cubit.dart"]);
}

#[test]
fn contains_mode_matches_basename() {
    let mut index = index(100);
    index.build().expect("index should build");

    let hits = index.query("ROUTER", FileMatchMode::Contains, 10);

    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].name, "app_router.dart");
    assert_eq!(hits[0].relative_path, "lib/app_router.dart");
}

#[test]
fn query_dirs_matches_basename() {
    let mut index = index(100);
    index.build().expect("index should build");

    assert_eq!(index.query_dirs("li", 10), ["lib"]);
}

#[test]
fn max_entries_truncates() {
    let mut index = index(1);
    index.build().expect("index should build");

    assert_eq!(index.file_count(), 1);
    assert!(index.truncated());
}
