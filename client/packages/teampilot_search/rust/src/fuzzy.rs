/// VSCode-Quick-Open-style subsequence score for `query` against `text`
/// (a relative file path). Returns a higher score for better matches and -1
/// when `query` is not a subsequence of `text`.
///
/// Heuristics, mirroring VSCode's Quick Open ranking:
/// - consecutive query characters in the target are the strongest signal;
/// - a match starting at a path-segment / underscore / dash / dot boundary or
///   a camelCase transition scores higher than a mid-word match;
/// - matches that start earlier in the path beat later ones;
/// - a match inside the basename (and especially a basename prefix) is worth
///   more than a match buried in the directory portion;
/// - a shorter relative path beats a longer one at equal match quality.
pub fn fuzzy_match_score(text: &str, query: &str) -> i32 {
    let target = text.to_lowercase();
    let q = query.to_lowercase();
    if q.is_empty() {
        return -1;
    }

    let target_units: Vec<u32> = target.encode_utf16().map(u32::from).collect();
    let q_units: Vec<u32> = q.encode_utf16().map(u32::from).collect();
    let text_units: Vec<u32> = text.encode_utf16().map(u32::from).collect();

    let mut score = 0i32;
    let mut search_from = 0usize;
    let mut run = 0i32;
    let mut previous_index = -1i32;

    for &ch in &q_units {
        let mut found = -1i32;
        for (i, &unit) in target_units.iter().enumerate().skip(search_from) {
            if unit == ch {
                found = i as i32;
                break;
            }
        }
        if found < 0 {
            return -1;
        }

        let found_usize = found as usize;
        let run_broken = previous_index >= 0 && found != previous_index + 1;
        if !run_broken {
            run += 1;
            score += 8 * run; // consecutive run bonus (grows with the run)
        } else {
            run = 1;
            score += boundary_bonus(&text_units, found_usize);
        }
        score += 1; // base per matched character
        score -= found / 8; // earlier position wins
        previous_index = found;
        search_from = found_usize + 1;
    }

    let slash = text.rfind('/').map(|i| i as i32).unwrap_or(-1);
    let base = if slash < 0 {
        text
    } else {
        &text[(slash as usize + 1)..]
    };
    let base_lower = base.to_lowercase();
    if base_lower.starts_with(&q) {
        score += 20;
    }
    if base_lower.contains(&q) {
        score += 12;
    }
    score -= (text.len() / 4) as i32; // shorter path preferred
    score
}

fn boundary_bonus(text_units: &[u32], index: usize) -> i32 {
    if index == 0 {
        return 6; // match at the very start of the path
    }
    let prev = text_units[index - 1];
    if prev == 0x2f || prev == 0x5f || prev == 0x2d || prev == 0x2e {
        return 6; // after `/`, `_`, `-`, `.`
    }
    let cur = text_units[index];
    let prev_char = char::from_u32(prev).unwrap_or('\0');
    let cur_char = char::from_u32(cur).unwrap_or('\0');
    let prev_upper = prev_char.to_uppercase().to_string() == prev_char.to_string()
        && prev_char.to_lowercase().to_string() != prev_char.to_string();
    let cur_lower = cur_char.to_lowercase().to_string() == cur_char.to_string()
        && cur_char.to_uppercase().to_string() != cur_char.to_string();
    if prev_upper && cur_lower {
        4 // camelCase boundary
    } else {
        0
    }
}
