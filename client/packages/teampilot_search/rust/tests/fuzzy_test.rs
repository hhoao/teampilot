use teampilot_search_rust::fuzzy::fuzzy_match_score;

#[test]
fn dart_parity_lib_app_router_router() {
    assert_eq!(fuzzy_match_score("lib/app_router.dart", "router"), 176);
}

#[test]
fn dart_parity_lib_chat_cubit_chat() {
    assert_eq!(fuzzy_match_score("lib/chat_cubit.dart", "chat"), 112);
}

#[test]
fn dart_parity_readme_md_readme() {
    assert_eq!(fuzzy_match_score("README.md", "readme"), 204);
}

#[test]
fn dart_parity_no_match() {
    assert_eq!(fuzzy_match_score("a/b/c.dart", "xyz"), -1);
}

#[test]
fn empty_query_is_no_match() {
    assert_eq!(fuzzy_match_score("lib/app_router.dart", ""), -1);
}

#[test]
fn subsequence_across_separators() {
    let score = fuzzy_match_score("lib/app_router.dart", "ppro");
    assert_eq!(score, 44);
    assert!(score > 0);
}

#[test]
fn basename_prefix_beats_directory_only() {
    let basename_score = fuzzy_match_score("lib/widgets/router_guard.dart", "router_guard");
    let directory_only_score = fuzzy_match_score("router/other.dart", "router_guard");
    assert_eq!(basename_score, 641);
    assert_eq!(directory_only_score, -1);
    assert!(basename_score > directory_only_score);
}

#[test]
fn cjk_path_uses_utf16_length_for_penalty() {
    // UTF-16 length is 9 (文档/a.dart); byte length is 13 — penalty must use 9/4=2 not 13/4=3.
    assert_eq!(fuzzy_match_score("文档/a.dart", "a"), 39);
}
