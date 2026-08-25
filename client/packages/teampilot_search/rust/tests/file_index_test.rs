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
    let hits = index.query("router", FileMatchMode::Fuzzy, 10);
    assert!(hits.iter().any(|hit| hit.path.ends_with("app_router.dart")));
    assert!(hits.iter().all(|hit| {
        !["secret", "ignored_dir", "node_modules", ".hidden"]
            .iter()
            .any(|excluded| hit.path.contains(excluded))
    }));
    let paths: Vec<_> = hits
        .into_iter()
        .map(|hit| hit.relative_path)
        .collect();
    assert_eq!(paths, ["lib/app_router.dart"]);
}

#[test]
fn fuzzy_mode_returns_router_file() {
    let mut index = index(100);
    index.build().expect("index should build");

    let hits = index.query("router", FileMatchMode::Fuzzy, 10);

    assert_eq!(hits.first().map(|hit| hit.name.as_str()), Some("app_router.dart"));
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
