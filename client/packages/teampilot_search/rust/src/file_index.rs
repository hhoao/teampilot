use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use ignore::{WalkBuilder, WalkState};

#[derive(Debug)]
pub enum FileIndexError {
    RootUnreadable,
    Internal(String),
}

pub struct FileIndexConfig {
    pub root: String,
    pub use_gitignore: bool,
    pub max_entries: u64,
}

pub enum FileMatchMode {
    Fuzzy,
    Contains,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileHit {
    pub path: String,
    pub relative_path: String,
    pub name: String,
}

pub struct FileIndex {
    config: FileIndexConfig,
    cancel: Arc<AtomicBool>,
    files: Vec<FileHit>,
    directories: Vec<String>,
    truncated: bool,
}

impl FileIndex {
    pub fn new(config: FileIndexConfig) -> Result<Self, FileIndexError> {
        if !Path::new(&config.root).is_dir() {
            return Err(FileIndexError::RootUnreadable);
        }
        Ok(Self {
            config,
            cancel: Arc::new(AtomicBool::new(false)),
            files: Vec::new(),
            directories: Vec::new(),
            truncated: false,
        })
    }

    pub fn build(&mut self) -> Result<(), FileIndexError> {
        let walker = build_walker(&self.config)?;
        let files = Arc::new(Mutex::new(Vec::new()));
        let directories = Arc::new(Mutex::new(Vec::new()));
        let stopped_for_limit = Arc::new(AtomicBool::new(false));
        let root = self.config.root.clone();
        let max_entries = self.config.max_entries;
        let cancel = self.cancel.clone();

        walker.build_parallel().run(|| {
            let files = files.clone();
            let directories = directories.clone();
            let stopped_for_limit = stopped_for_limit.clone();
            let cancel = cancel.clone();
            let root = root.clone();

            Box::new(move |entry| {
                if cancel.load(Ordering::Relaxed) || stopped_for_limit.load(Ordering::Relaxed) {
                    return WalkState::Quit;
                }
                let entry = match entry {
                    Ok(entry) => entry,
                    Err(_) => return WalkState::Continue,
                };
                let path = entry.path();
                if entry.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                    let directory = relative_path(path, &root);
                    if !directory.is_empty() {
                        if let Ok(mut directories) = directories.lock() {
                            if !directories.contains(&directory) {
                                directories.push(directory);
                            }
                        } else {
                            return WalkState::Quit;
                        }
                    }
                    return WalkState::Continue;
                }
                if !entry.file_type().map(|ft| ft.is_file()).unwrap_or(false) {
                    return WalkState::Continue;
                }

                let relative_path = relative_path(path, &root);
                let name = path
                    .file_name()
                    .map(|name| name.to_string_lossy().into_owned())
                    .unwrap_or_default();
                let hit = FileHit {
                    path: path.to_string_lossy().replace('\\', "/"),
                    relative_path: relative_path.clone(),
                    name,
                };
                if let Ok(mut files) = files.lock() {
                    if max_entries > 0 && files.len() as u64 >= max_entries {
                        stopped_for_limit.store(true, Ordering::Relaxed);
                        return WalkState::Quit;
                    }
                    files.push(hit);
                    if max_entries > 0 && files.len() as u64 >= max_entries {
                        stopped_for_limit.store(true, Ordering::Relaxed);
                    }
                } else {
                    return WalkState::Quit;
                }

                if cancel.load(Ordering::Relaxed) || stopped_for_limit.load(Ordering::Relaxed) {
                    WalkState::Quit
                } else {
                    WalkState::Continue
                }
            })
        });

        self.files = Arc::try_unwrap(files)
            .map_err(|_| FileIndexError::Internal("file collection still shared".into()))?
            .into_inner()
            .map_err(|_| FileIndexError::Internal("file collection lock poisoned".into()))?;
        self.directories = Arc::try_unwrap(directories)
            .map_err(|_| FileIndexError::Internal("directory collection still shared".into()))?
            .into_inner()
            .map_err(|_| FileIndexError::Internal("directory collection lock poisoned".into()))?;
        self.truncated = stopped_for_limit.load(Ordering::Relaxed);
        Ok(())
    }

    pub fn cancel(&self) {
        self.cancel.store(true, Ordering::Relaxed);
    }

    pub fn query(&self, q: &str, mode: FileMatchMode, limit: usize) -> Vec<FileHit> {
        if limit == 0 || q.trim().is_empty() {
            return Vec::new();
        }
        match mode {
            FileMatchMode::Fuzzy => {
                let mut matches: Vec<_> = self
                    .files
                    .iter()
                    .filter_map(|hit| {
                        let score = crate::fuzzy::fuzzy_match_score(&hit.relative_path, q);
                        (score >= 0).then(|| (score, hit))
                    })
                    .collect();
                matches.sort_unstable_by(|(score_a, hit_a), (score_b, hit_b)| {
                    score_b
                        .cmp(score_a)
                        .then_with(|| hit_a.relative_path.cmp(&hit_b.relative_path))
                });
                matches
                    .into_iter()
                    .take(limit)
                    .map(|(_, hit)| hit.clone())
                    .collect()
            }
            FileMatchMode::Contains => {
                let query = q.to_lowercase();
                self.files
                    .iter()
                    .filter(|hit| hit.name.to_lowercase().contains(&query))
                    .take(limit)
                    .cloned()
                    .collect()
            }
        }
    }

    pub fn query_dirs(&self, q: &str, limit: usize) -> Vec<String> {
        if limit == 0 || q.trim().is_empty() {
            return Vec::new();
        }
        let query = q.to_lowercase();
        self.directories
            .iter()
            .filter(|path| {
                let name = Path::new(path)
                    .file_name()
                    .unwrap_or_default()
                    .to_string_lossy();
                name.to_lowercase().contains(&query)
            })
            .take(limit)
            .cloned()
            .collect()
    }

    pub fn truncated(&self) -> bool {
        self.truncated
    }

    pub fn file_count(&self) -> usize {
        self.files.len()
    }
}

fn build_walker(config: &FileIndexConfig) -> Result<WalkBuilder, FileIndexError> {
    if !Path::new(&config.root).is_dir() {
        return Err(FileIndexError::RootUnreadable);
    }
    let mut walker = WalkBuilder::new(&config.root);
    walker
        .hidden(true)
        .ignore(config.use_gitignore)
        .git_ignore(config.use_gitignore)
        .git_global(false)
        .git_exclude(false)
        .require_git(false)
        .parents(true)
        .follow_links(false);
    Ok(walker)
}

fn relative_path(path: &Path, root: &str) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}
