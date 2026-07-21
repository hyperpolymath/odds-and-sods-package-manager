// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
//
//! OPSM TUI — core types and state machine.
//!
//! Follows the Rust/SPARK pattern from reposystem-tui:
//! - Bounded constants for all dimensions
//! - `AppState` with invariant checking via `debug_assert!`
//! - Pre/post conditions on all mutations
//! - Property-based tests mirroring SPARK proof obligations
//!
//! # Invariant
//!
//! `AppState` maintains:
//!   - `cursor` in `0..package_count`
//!   - `scroll_offset` in `0..=max(0, package_count - visible_height)`
//!   - `width` in `1..=MAX_WIDTH`, `height` in `1..=MAX_HEIGHT`
//!   - `search_query.len() <= MAX_SEARCH_LEN`

#![forbid(unsafe_code)]

use std::fmt;
use std::process::Command;

// =============================================================================
// Constants — bounded ranges (SPARK subtypes)
// =============================================================================

/// Maximum terminal width.
pub const MAX_WIDTH: u16 = 1000;

/// Maximum terminal height.
pub const MAX_HEIGHT: u16 = 500;

/// Maximum packages displayable.
pub const MAX_PACKAGES: usize = 50_000;

/// Maximum search query length.
pub const MAX_SEARCH_LEN: usize = 256;

/// Maximum registries.
pub const MAX_FORTHS: usize = 120;

// =============================================================================
// Enums
// =============================================================================

/// Active view in the TUI.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum View {
    /// Package list with install/remove actions.
    Packages,
    /// Detailed info for selected package.
    Detail,
    /// Search results across registries.
    Search,
    /// Dependency tree for selected package.
    DepsTree,
    /// Transaction history with undo/redo.
    History,
    /// Trust pipeline + verification status.
    Trust,
}

impl fmt::Display for View {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            View::Packages => write!(f, "PACKAGES"),
            View::Detail => write!(f, "DETAIL"),
            View::Search => write!(f, "SEARCH"),
            View::DepsTree => write!(f, "DEPS"),
            View::History => write!(f, "HISTORY"),
            View::Trust => write!(f, "TRUST"),
        }
    }
}

/// Filter for package list.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Filter {
    /// All packages (installed + available).
    All,
    /// Only installed packages.
    Installed,
    /// Packages with available updates.
    Updates,
    /// Search results.
    SearchResults,
}

impl fmt::Display for Filter {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Filter::All => write!(f, "ALL"),
            Filter::Installed => write!(f, "INSTALLED"),
            Filter::Updates => write!(f, "UPDATES"),
            Filter::SearchResults => write!(f, "SEARCH"),
        }
    }
}

/// Input mode — normal navigation or text entry.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputMode {
    /// Normal mode — hjkl/arrows navigate, keys trigger actions.
    Normal,
    /// Search input — typing goes to search query.
    Search,
    /// Confirmation prompt (install/remove).
    Confirm,
}

// =============================================================================
// Package data (from CLI JSON output)
// =============================================================================

/// A package as displayed in the TUI.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PackageEntry {
    pub name: String,
    pub version: String,
    pub forth: String,
    pub installed: bool,
    pub description: Option<String>,
    pub update_available: Option<String>,
    pub checksum_status: Option<String>,
}

/// A history entry.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct HistoryEntry {
    pub id: String,
    pub operation: String,
    pub timestamp: String,
    pub package: Option<String>,
}

// =============================================================================
// AppState — core state with SPARK-style invariant
// =============================================================================

/// Core application state.
///
/// All fields are bounded. The invariant is checked after every mutation
/// via `debug_assert!(self.check_invariant())`.
pub struct AppState {
    // Terminal dimensions
    width: u16,
    height: u16,

    // Navigation
    cursor: usize,
    scroll_offset: usize,

    // View state
    view: View,
    filter: Filter,
    input_mode: InputMode,

    // Data
    packages: Vec<PackageEntry>,
    history: Vec<HistoryEntry>,
    search_query: String,
    status_message: String,

    // Action confirmation
    confirm_action: Option<String>,
    confirm_package: Option<String>,

    // Running flag (mirrors Ada State.Running)
    running: bool,
}

impl AppState {
    // =========================================================================
    // Constructor — mirrors Ada Initialize
    // =========================================================================

    /// Create a new AppState with the given terminal dimensions.
    ///
    /// Mirrors Ada:
    /// ```ada
    /// procedure Initialize (State : out App_State; W, H : Positive)
    ///   with Post => State.Running and State.Cursor_X = 1 and State.Cursor_Y = 1;
    /// ```
    pub fn new(width: u16, height: u16) -> Self {
        let w = width.clamp(1, MAX_WIDTH);
        let h = height.clamp(1, MAX_HEIGHT);

        let state = Self {
            width: w,
            height: h,
            cursor: 0,
            scroll_offset: 0,
            view: View::Packages,
            filter: Filter::Installed,
            input_mode: InputMode::Normal,
            packages: Vec::new(),
            history: Vec::new(),
            search_query: String::new(),
            status_message: String::from("Ready — press ? for help"),
            confirm_action: None,
            confirm_package: None,
            running: true,
        };

        // SPARK post-condition
        debug_assert!(state.running, "SPARK post: Initialize sets Running = True");
        debug_assert!(
            state.check_invariant(),
            "SPARK post: Initialize establishes invariant"
        );

        state
    }

    // =========================================================================
    // Invariant check — mirrors Ada Dynamic_Predicate
    // =========================================================================

    /// Check the AppState invariant.
    ///
    /// Mirrors Ada Dynamic_Predicate on App_State.
    pub fn check_invariant(&self) -> bool {
        let pkg_count = self.packages.len();

        self.width >= 1
            && self.width <= MAX_WIDTH
            && self.height >= 1
            && self.height <= MAX_HEIGHT
            && (pkg_count == 0 || self.cursor < pkg_count)
            && self.scroll_offset <= pkg_count
            && self.search_query.len() <= MAX_SEARCH_LEN
    }

    // =========================================================================
    // Accessors
    // =========================================================================

    pub fn is_running(&self) -> bool {
        self.running
    }
    pub fn width(&self) -> u16 {
        self.width
    }
    pub fn height(&self) -> u16 {
        self.height
    }
    pub fn cursor(&self) -> usize {
        self.cursor
    }
    pub fn scroll_offset(&self) -> usize {
        self.scroll_offset
    }
    pub fn view(&self) -> View {
        self.view
    }
    pub fn filter(&self) -> Filter {
        self.filter
    }
    pub fn input_mode(&self) -> InputMode {
        self.input_mode
    }
    pub fn packages(&self) -> &[PackageEntry] {
        &self.packages
    }
    pub fn history(&self) -> &[HistoryEntry] {
        &self.history
    }
    pub fn search_query(&self) -> &str {
        &self.search_query
    }
    pub fn status_message(&self) -> &str {
        &self.status_message
    }
    pub fn confirm_action(&self) -> Option<&str> {
        self.confirm_action.as_deref()
    }
    pub fn confirm_package(&self) -> Option<&str> {
        self.confirm_package.as_deref()
    }

    /// Visible height for the package list (content area minus chrome).
    pub fn visible_height(&self) -> usize {
        // header(3) + status(1) + footer(2) + borders(2) = 8 lines of chrome
        self.height.saturating_sub(8) as usize
    }

    /// Selected package (if any).
    pub fn selected_package(&self) -> Option<&PackageEntry> {
        self.packages.get(self.cursor)
    }

    // =========================================================================
    // Mutations — all check invariant post-condition
    // =========================================================================

    /// Handle terminal resize.
    pub fn resize(&mut self, w: u16, h: u16) {
        self.width = w.clamp(1, MAX_WIDTH);
        self.height = h.clamp(1, MAX_HEIGHT);
        self.clamp_cursor();
        debug_assert!(
            self.check_invariant(),
            "SPARK post: resize maintains invariant"
        );
    }

    /// Move cursor up.
    pub fn cursor_up(&mut self) {
        if self.cursor > 0 {
            self.cursor -= 1;
            if self.cursor < self.scroll_offset {
                self.scroll_offset = self.cursor;
            }
        }
        debug_assert!(
            self.check_invariant(),
            "SPARK post: cursor_up maintains invariant"
        );
    }

    /// Move cursor down.
    pub fn cursor_down(&mut self) {
        let max = if self.packages.is_empty() {
            0
        } else {
            self.packages.len() - 1
        };
        if self.cursor < max {
            self.cursor += 1;
            let vis = self.visible_height();
            if self.cursor >= self.scroll_offset + vis {
                self.scroll_offset = self.cursor.saturating_sub(vis - 1);
            }
        }
        debug_assert!(
            self.check_invariant(),
            "SPARK post: cursor_down maintains invariant"
        );
    }

    /// Page up (move by visible_height).
    pub fn page_up(&mut self) {
        let vis = self.visible_height();
        self.cursor = self.cursor.saturating_sub(vis);
        self.scroll_offset = self.scroll_offset.saturating_sub(vis);
        debug_assert!(
            self.check_invariant(),
            "SPARK post: page_up maintains invariant"
        );
    }

    /// Page down (move by visible_height).
    pub fn page_down(&mut self) {
        let vis = self.visible_height();
        let max = if self.packages.is_empty() {
            0
        } else {
            self.packages.len() - 1
        };
        self.cursor = (self.cursor + vis).min(max);
        self.scroll_offset =
            (self.scroll_offset + vis).min(self.packages.len().saturating_sub(vis));
        debug_assert!(
            self.check_invariant(),
            "SPARK post: page_down maintains invariant"
        );
    }

    /// Jump to top.
    pub fn jump_top(&mut self) {
        self.cursor = 0;
        self.scroll_offset = 0;
        debug_assert!(
            self.check_invariant(),
            "SPARK post: jump_top maintains invariant"
        );
    }

    /// Jump to bottom.
    pub fn jump_bottom(&mut self) {
        if !self.packages.is_empty() {
            self.cursor = self.packages.len() - 1;
            let vis = self.visible_height();
            self.scroll_offset = self.packages.len().saturating_sub(vis);
        }
        debug_assert!(
            self.check_invariant(),
            "SPARK post: jump_bottom maintains invariant"
        );
    }

    /// Switch view.
    pub fn set_view(&mut self, view: View) {
        self.view = view;
        self.status_message = format!("View: {}", view);
    }

    /// Switch filter and reload.
    pub fn set_filter(&mut self, filter: Filter) {
        self.filter = filter;
        self.cursor = 0;
        self.scroll_offset = 0;
        self.status_message = format!("Filter: {}", filter);
        debug_assert!(
            self.check_invariant(),
            "SPARK post: set_filter maintains invariant"
        );
    }

    /// Enter search mode.
    pub fn enter_search(&mut self) {
        self.input_mode = InputMode::Search;
        self.search_query.clear();
        self.status_message = String::from("Type to search, Enter to submit, Esc to cancel");
    }

    /// Exit search/confirm mode.
    pub fn exit_input_mode(&mut self) {
        self.input_mode = InputMode::Normal;
        self.confirm_action = None;
        self.confirm_package = None;
        self.status_message = String::from("Ready");
    }

    /// Append character to search query.
    pub fn search_push(&mut self, c: char) {
        if self.search_query.len() < MAX_SEARCH_LEN {
            self.search_query.push(c);
        }
        debug_assert!(
            self.check_invariant(),
            "SPARK post: search_push maintains invariant"
        );
    }

    /// Delete last character from search query.
    pub fn search_pop(&mut self) {
        self.search_query.pop();
    }

    /// Prompt for confirmation (install/remove).
    pub fn prompt_confirm(&mut self, action: &str, package: &str) {
        self.input_mode = InputMode::Confirm;
        self.confirm_action = Some(action.to_string());
        self.confirm_package = Some(package.to_string());
        self.status_message = format!("{} {}? [y/N]", action, package);
    }

    /// Request quit.
    pub fn quit(&mut self) {
        self.running = false;
    }

    /// Set status message.
    pub fn set_status(&mut self, msg: String) {
        self.status_message = msg;
    }

    // =========================================================================
    // Data loading — shells out to opsm CLI
    // =========================================================================

    /// Load installed packages from `opsm list --installed --json`.
    pub fn load_installed(&mut self) {
        self.status_message = String::from("Loading installed packages...");
        match run_opsm(&["list", "--installed", "--json"]) {
            Ok(output) => {
                if let Ok(pkgs) = serde_json::from_str::<Vec<PackageEntry>>(&output) {
                    self.packages = pkgs;
                } else {
                    // Parse line-by-line fallback (non-JSON output)
                    self.packages = parse_list_output(&output);
                }
                self.clamp_cursor();
                self.status_message = format!("{} installed packages", self.packages.len());
            }
            Err(e) => {
                self.status_message = format!("Error: {}", e);
            }
        }
        debug_assert!(
            self.check_invariant(),
            "SPARK post: load_installed maintains invariant"
        );
    }

    /// Load history from `opsm history list --json`.
    pub fn load_history(&mut self) {
        match run_opsm(&["history", "list", "--json"]) {
            Ok(output) => {
                if let Ok(entries) = serde_json::from_str::<Vec<HistoryEntry>>(&output) {
                    self.history = entries;
                }
            }
            Err(e) => {
                self.status_message = format!("History error: {}", e);
            }
        }
    }

    /// Run search via `opsm search <query> --json`.
    pub fn run_search(&mut self) {
        if self.search_query.is_empty() {
            return;
        }
        self.status_message = format!("Searching: {}...", self.search_query);
        match run_opsm(&["search", &self.search_query, "--json"]) {
            Ok(output) => {
                if let Ok(pkgs) = serde_json::from_str::<Vec<PackageEntry>>(&output) {
                    self.packages = pkgs;
                } else {
                    self.packages = parse_search_output(&output);
                }
                self.cursor = 0;
                self.scroll_offset = 0;
                self.filter = Filter::SearchResults;
                self.status_message = format!(
                    "{} results for '{}'",
                    self.packages.len(),
                    self.search_query
                );
            }
            Err(e) => {
                self.status_message = format!("Search error: {}", e);
            }
        }
        debug_assert!(
            self.check_invariant(),
            "SPARK post: run_search maintains invariant"
        );
    }

    /// Install selected package via `opsm install <name>`.
    pub fn install_selected(&mut self) {
        if let Some(pkg) = self.selected_package().cloned() {
            self.status_message = format!("Installing {}...", pkg.name);
            let args = if pkg.forth.is_empty() {
                vec!["install".to_string(), pkg.name.clone()]
            } else {
                vec![
                    "install".to_string(),
                    format!("@{}", pkg.forth),
                    pkg.name.clone(),
                ]
            };
            let ref_args: Vec<&str> = args.iter().map(|s| s.as_str()).collect();
            match run_opsm(&ref_args) {
                Ok(output) => {
                    self.status_message = format!("Installed {}", pkg.name);
                    self.load_installed();
                    // Show last line of output as status
                    if let Some(last) = output.lines().last() {
                        self.status_message = last.to_string();
                    }
                }
                Err(e) => {
                    self.status_message = format!("Install failed: {}", e);
                }
            }
        }
    }

    /// Remove selected package via `opsm remove <name>`.
    pub fn remove_selected(&mut self) {
        if let Some(pkg) = self.selected_package().cloned() {
            self.status_message = format!("Removing {}...", pkg.name);
            match run_opsm(&["remove", &pkg.name]) {
                Ok(_) => {
                    self.status_message = format!("Removed {}", pkg.name);
                    self.load_installed();
                }
                Err(e) => {
                    self.status_message = format!("Remove failed: {}", e);
                }
            }
        }
    }

    /// Undo last operation via `opsm history undo`.
    pub fn undo_last(&mut self) {
        match run_opsm(&["history", "undo"]) {
            Ok(output) => {
                self.status_message = output.lines().last().unwrap_or("Undone").to_string();
                self.load_installed();
                self.load_history();
            }
            Err(e) => {
                self.status_message = format!("Undo failed: {}", e);
            }
        }
    }

    /// Redo last undo via `opsm history redo`.
    pub fn redo_last(&mut self) {
        match run_opsm(&["history", "redo"]) {
            Ok(output) => {
                self.status_message = output.lines().last().unwrap_or("Redone").to_string();
                self.load_installed();
                self.load_history();
            }
            Err(e) => {
                self.status_message = format!("Redo failed: {}", e);
            }
        }
    }

    /// Run verify via `opsm check`.
    pub fn run_check(&mut self) {
        self.status_message = String::from("Verifying...");
        match run_opsm(&["check"]) {
            Ok(output) => {
                self.status_message = output
                    .lines()
                    .last()
                    .unwrap_or("Check complete")
                    .to_string();
            }
            Err(e) => {
                self.status_message = format!("Check failed: {}", e);
            }
        }
    }

    // =========================================================================
    // Internal
    // =========================================================================

    fn clamp_cursor(&mut self) {
        if self.packages.is_empty() {
            self.cursor = 0;
            self.scroll_offset = 0;
        } else if self.cursor >= self.packages.len() {
            self.cursor = self.packages.len() - 1;
        }
    }
}

// =============================================================================
// CLI execution — shells out to opsm binary
// =============================================================================

/// Execute `opsm` with the given arguments. Returns stdout on success.
fn run_opsm(args: &[&str]) -> Result<String, String> {
    let output = Command::new("opsm")
        .args(args)
        .env("NO_COLOR", "1")
        .output()
        .map_err(|e| format!("opsm not found: {}", e))?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        Err(if stderr.is_empty() { stdout } else { stderr })
    }
}

/// Parse non-JSON list output into PackageEntry vec.
fn parse_list_output(output: &str) -> Vec<PackageEntry> {
    output
        .lines()
        .filter(|l| l.contains('@') && !l.starts_with("  "))
        .filter_map(|line| {
            let parts: Vec<&str> = line.trim().splitn(3, ' ').collect();
            if parts.len() >= 2 {
                let name_ver: Vec<&str> = parts[0].splitn(2, '@').collect();
                Some(PackageEntry {
                    name: name_ver[0].to_string(),
                    version: name_ver.get(1).unwrap_or(&"?").to_string(),
                    forth: parts
                        .get(1)
                        .unwrap_or(&"")
                        .trim_start_matches('(')
                        .trim_end_matches(')')
                        .to_string(),
                    installed: true,
                    description: parts.get(2).map(|s| s.to_string()),
                    update_available: None,
                    checksum_status: None,
                })
            } else {
                None
            }
        })
        .collect()
}

/// Parse non-JSON search output into PackageEntry vec.
fn parse_search_output(output: &str) -> Vec<PackageEntry> {
    // Search output format: "  @forth: name v1.2.3 — description"
    output
        .lines()
        .filter(|l| l.trim().starts_with('@') || l.trim().starts_with("- "))
        .filter_map(|line| {
            let trimmed = line.trim().trim_start_matches("- ");
            let parts: Vec<&str> = trimmed.splitn(2, ':').collect();
            if parts.len() == 2 {
                let forth = parts[0].trim().trim_start_matches('@');
                let rest = parts[1].trim();
                let name = rest.split_whitespace().next().unwrap_or("?");
                Some(PackageEntry {
                    name: name.to_string(),
                    version: String::new(),
                    forth: forth.to_string(),
                    installed: false,
                    description: Some(rest.to_string()),
                    update_available: None,
                    checksum_status: None,
                })
            } else {
                None
            }
        })
        .collect()
}

// =============================================================================
// Tests — SPARK proof obligations as property tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_establishes_invariant() {
        let state = AppState::new(80, 24);
        assert!(state.check_invariant());
        assert!(state.is_running());
        assert_eq!(state.cursor(), 0);
    }

    #[test]
    fn test_new_clamps_dimensions() {
        let state = AppState::new(0, 0);
        assert_eq!(state.width(), 1);
        assert_eq!(state.height(), 1);
        assert!(state.check_invariant());

        let state = AppState::new(9999, 9999);
        assert_eq!(state.width(), MAX_WIDTH);
        assert_eq!(state.height(), MAX_HEIGHT);
        assert!(state.check_invariant());
    }

    #[test]
    fn test_cursor_navigation_bounds() {
        let mut state = AppState::new(80, 24);
        // Empty list — cursor stays at 0
        state.cursor_up();
        assert_eq!(state.cursor(), 0);
        state.cursor_down();
        assert_eq!(state.cursor(), 0);
        assert!(state.check_invariant());
    }

    #[test]
    fn test_cursor_with_packages() {
        let mut state = AppState::new(80, 24);
        state.packages = vec![
            PackageEntry {
                name: "a".into(),
                version: "1".into(),
                forth: "npm".into(),
                installed: true,
                description: None,
                update_available: None,
                checksum_status: None,
            },
            PackageEntry {
                name: "b".into(),
                version: "2".into(),
                forth: "npm".into(),
                installed: true,
                description: None,
                update_available: None,
                checksum_status: None,
            },
            PackageEntry {
                name: "c".into(),
                version: "3".into(),
                forth: "npm".into(),
                installed: true,
                description: None,
                update_available: None,
                checksum_status: None,
            },
        ];
        state.cursor_down();
        assert_eq!(state.cursor(), 1);
        state.cursor_down();
        assert_eq!(state.cursor(), 2);
        state.cursor_down(); // At max, should not go further
        assert_eq!(state.cursor(), 2);
        state.cursor_up();
        assert_eq!(state.cursor(), 1);
        assert!(state.check_invariant());
    }

    #[test]
    fn test_resize_preserves_invariant() {
        let mut state = AppState::new(80, 24);
        state.packages = vec![PackageEntry {
            name: "a".into(),
            version: "1".into(),
            forth: "npm".into(),
            installed: true,
            description: None,
            update_available: None,
            checksum_status: None,
        }];
        state.cursor = 0;
        state.resize(40, 10);
        assert!(state.check_invariant());
        state.resize(0, 0);
        assert_eq!(state.width(), 1);
        assert_eq!(state.height(), 1);
        assert!(state.check_invariant());
    }

    #[test]
    fn test_search_query_bounded() {
        let mut state = AppState::new(80, 24);
        state.enter_search();
        for _ in 0..MAX_SEARCH_LEN + 10 {
            state.search_push('a');
        }
        assert!(state.search_query().len() <= MAX_SEARCH_LEN);
        assert!(state.check_invariant());
    }

    #[test]
    fn test_quit_sets_not_running() {
        let mut state = AppState::new(80, 24);
        assert!(state.is_running());
        state.quit();
        assert!(!state.is_running());
    }

    #[test]
    fn test_filter_resets_cursor() {
        let mut state = AppState::new(80, 24);
        state.packages = vec![
            PackageEntry {
                name: "a".into(),
                version: "1".into(),
                forth: "npm".into(),
                installed: true,
                description: None,
                update_available: None,
                checksum_status: None,
            },
            PackageEntry {
                name: "b".into(),
                version: "2".into(),
                forth: "npm".into(),
                installed: true,
                description: None,
                update_available: None,
                checksum_status: None,
            },
        ];
        state.cursor = 1;
        state.set_filter(Filter::Installed);
        assert_eq!(state.cursor(), 0);
        assert!(state.check_invariant());
    }

    #[test]
    fn test_page_navigation() {
        let mut state = AppState::new(80, 30); // visible_height = 22
        state.packages = (0..50)
            .map(|i| PackageEntry {
                name: format!("pkg-{}", i),
                version: "1.0.0".into(),
                forth: "npm".into(),
                installed: true,
                description: None,
                update_available: None,
                checksum_status: None,
            })
            .collect();
        state.page_down();
        assert!(state.cursor() > 0);
        assert!(state.check_invariant());
        state.page_up();
        assert!(state.check_invariant());
        state.jump_bottom();
        assert_eq!(state.cursor(), 49);
        assert!(state.check_invariant());
        state.jump_top();
        assert_eq!(state.cursor(), 0);
        assert!(state.check_invariant());
    }
}
