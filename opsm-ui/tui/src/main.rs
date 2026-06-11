// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
//
//! OPSM TUI — terminal user interface for the Odds and Sods Package Manager.
//!
//! Better than aptitude: split panes, cross-registry search, trust dashboard,
//! transaction history with undo/redo, dependency tree viewer.
//!
//! Follows the Rust/SPARK pattern from reposystem-tui.

#![forbid(unsafe_code)]

use std::io;
use std::time::Duration;

use clap::Parser;
use crossterm::{
    event::{self, Event, KeyCode, KeyEvent, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    prelude::CrosstermBackend,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame, Terminal,
};

use opsm_tui::{AppState, Filter, InputMode, View};

// =============================================================================
// Catppuccin Mocha colours (matches panel.html theme)
// =============================================================================

const BG: Color = Color::Rgb(30, 30, 46);
const SURFACE: Color = Color::Rgb(49, 50, 68);
const TEXT: Color = Color::Rgb(205, 214, 244);
const SUBTEXT: Color = Color::Rgb(166, 173, 200);
const ACCENT: Color = Color::Rgb(137, 180, 250);
const GREEN: Color = Color::Rgb(166, 227, 161);
const YELLOW: Color = Color::Rgb(249, 226, 175);
const RED: Color = Color::Rgb(243, 139, 168);
const BORDER: Color = Color::Rgb(69, 71, 90);

// =============================================================================
// CLI arguments
// =============================================================================

/// OPSM TUI — terminal interface for the Odds and Sods Package Manager.
#[derive(Parser, Debug)]
#[command(name = "opsm-tui", version, about)]
struct Cli {
    /// Start in search mode with this query.
    #[arg(short, long)]
    search: Option<String>,

    /// Show only installed packages on start.
    #[arg(short, long)]
    installed: bool,
}

// =============================================================================
// Rendering
// =============================================================================

/// Render the full TUI frame.
///
/// Layout: header(3) | content(min 5) | status(1) | footer(1)
fn render(frame: &mut Frame, state: &AppState) {
    debug_assert!(state.is_running(), "SPARK pre: Render requires State.Running");

    let area = frame.area();

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),  // Header
            Constraint::Min(5),    // Content
            Constraint::Length(1), // Status bar
            Constraint::Length(2), // Footer / keybindings
        ])
        .split(area);

    render_header(frame, state, chunks[0]);
    render_content(frame, state, chunks[1]);
    render_status(frame, state, chunks[2]);
    render_footer(frame, state, chunks[3]);
}

/// Header bar with title and filter tabs.
fn render_header(frame: &mut Frame, state: &AppState, area: Rect) {
    let tabs = vec![
        ("1:Installed", Filter::Installed),
        ("2:Updates", Filter::Updates),
        ("3:Search", Filter::SearchResults),
        ("4:All", Filter::All),
    ];

    let mut spans: Vec<Span> = vec![
        Span::styled(
            " OPSM ",
            Style::default().fg(Color::White).bg(ACCENT).add_modifier(Modifier::BOLD),
        ),
        Span::raw(" "),
    ];

    for (label, filter) in &tabs {
        let style = if *filter == state.filter() {
            Style::default().fg(BG).bg(ACCENT).add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(SUBTEXT)
        };
        spans.push(Span::styled(format!(" {} ", label), style));
        spans.push(Span::raw(" "));
    }

    spans.push(Span::styled(
        format!(" [{}] ", state.view()),
        Style::default().fg(YELLOW),
    ));

    let header = Paragraph::new(Line::from(spans))
        .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(BORDER)));
    frame.render_widget(header, area);
}

/// Main content area — package list (left) + detail (right) in split pane.
fn render_content(frame: &mut Frame, state: &AppState, area: Rect) {
    match state.view() {
        View::Packages | View::Search => {
            // Split: package list (60%) | detail panel (40%)
            let chunks = Layout::default()
                .direction(Direction::Horizontal)
                .constraints([Constraint::Percentage(60), Constraint::Percentage(40)])
                .split(area);

            render_package_list(frame, state, chunks[0]);
            render_detail_panel(frame, state, chunks[1]);
        }
        View::History => render_history_view(frame, state, area),
        View::DepsTree => render_deps_view(frame, state, area),
        View::Trust => render_trust_view(frame, state, area),
        View::Detail => render_full_detail(frame, state, area),
    }
}

/// Package list with selection cursor.
fn render_package_list(frame: &mut Frame, state: &AppState, area: Rect) {
    let packages = state.packages();
    let offset = state.scroll_offset();
    let cursor = state.cursor();

    let visible = area.height.saturating_sub(2) as usize; // minus borders
    let end = (offset + visible).min(packages.len());

    let items: Vec<ListItem> = packages[offset..end]
        .iter()
        .enumerate()
        .map(|(i, pkg)| {
            let idx = offset + i;
            let selected = idx == cursor;

            let status_icon = if pkg.installed {
                Span::styled("● ", Style::default().fg(GREEN))
            } else {
                Span::styled("○ ", Style::default().fg(SUBTEXT))
            };

            let name_style = if selected {
                Style::default().fg(BG).bg(ACCENT).add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(TEXT)
            };

            let version_style = Style::default().fg(SUBTEXT);
            let forth_style = Style::default().fg(YELLOW);

            let mut spans = vec![
                status_icon,
                Span::styled(&pkg.name, name_style),
                Span::styled(format!(" {}", pkg.version), version_style),
            ];

            if !pkg.forth.is_empty() {
                spans.push(Span::styled(format!(" @{}", pkg.forth), forth_style));
            }

            if let Some(ref update) = pkg.update_available {
                spans.push(Span::styled(format!(" -> {}", update), Style::default().fg(GREEN)));
            }

            ListItem::new(Line::from(spans))
        })
        .collect();

    let title = format!(" Packages ({}) ", packages.len());
    let list = List::new(items)
        .block(
            Block::default()
                .title(title)
                .borders(Borders::ALL)
                .border_style(Style::default().fg(BORDER)),
        );

    frame.render_widget(list, area);
}

/// Detail panel showing selected package info.
fn render_detail_panel(frame: &mut Frame, state: &AppState, area: Rect) {
    let content = if let Some(pkg) = state.selected_package() {
        let mut lines = vec![
            Line::from(Span::styled(&pkg.name, Style::default().fg(ACCENT).add_modifier(Modifier::BOLD))),
            Line::from(Span::styled(format!("v{}", pkg.version), Style::default().fg(TEXT))),
            Line::from(Span::styled(format!("@{}", pkg.forth), Style::default().fg(YELLOW))),
            Line::from(""),
            Line::from(Span::styled(
                if pkg.installed { "Status: Installed" } else { "Status: Available" },
                Style::default().fg(if pkg.installed { GREEN } else { SUBTEXT }),
            )),
        ];

        if let Some(ref desc) = pkg.description {
            lines.push(Line::from(""));
            lines.push(Line::from(Span::styled(desc.as_str(), Style::default().fg(SUBTEXT))));
        }

        if let Some(ref cs) = pkg.checksum_status {
            lines.push(Line::from(""));
            lines.push(Line::from(Span::styled(format!("Checksum: {}", cs), Style::default().fg(SUBTEXT))));
        }

        lines.push(Line::from(""));
        lines.push(Line::from(""));
        if pkg.installed {
            lines.push(Line::from(Span::styled("  [r] Remove  [R] Reinstall", Style::default().fg(RED))));
        } else {
            lines.push(Line::from(Span::styled("  [i] Install", Style::default().fg(GREEN))));
        }
        lines.push(Line::from(Span::styled("  [d] Deps  [Enter] Full detail", Style::default().fg(SUBTEXT))));

        lines
    } else {
        vec![
            Line::from(Span::styled("No package selected", Style::default().fg(SUBTEXT))),
        ]
    };

    let detail = Paragraph::new(content)
        .block(
            Block::default()
                .title(" Detail ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(BORDER)),
        )
        .wrap(Wrap { trim: true });

    frame.render_widget(detail, area);
}

/// History view.
fn render_history_view(frame: &mut Frame, state: &AppState, area: Rect) {
    let items: Vec<ListItem> = state.history().iter().map(|entry| {
        let pkg_str = entry.package.as_deref().unwrap_or("");
        let style = match entry.operation.as_str() {
            op if op.contains("install") => Style::default().fg(GREEN),
            op if op.contains("remove") => Style::default().fg(RED),
            op if op.contains("undo") => Style::default().fg(YELLOW),
            _ => Style::default().fg(TEXT),
        };
        ListItem::new(Line::from(vec![
            Span::styled(&entry.timestamp[..19.min(entry.timestamp.len())], Style::default().fg(SUBTEXT)),
            Span::raw("  "),
            Span::styled(&entry.operation, style),
            Span::raw("  "),
            Span::styled(pkg_str, Style::default().fg(ACCENT)),
        ]))
    }).collect();

    let list = List::new(items)
        .block(
            Block::default()
                .title(" History [u]ndo [r]edo ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(BORDER)),
        );

    frame.render_widget(list, area);
}

/// Dependency tree view (placeholder — calls opsm depends).
fn render_deps_view(frame: &mut Frame, state: &AppState, area: Rect) {
    let content = if let Some(pkg) = state.selected_package() {
        format!("Dependencies for {}@{} (@{})\n\nPress 'd' in packages view to load.", pkg.name, pkg.version, pkg.forth)
    } else {
        "Select a package first".to_string()
    };

    let widget = Paragraph::new(content)
        .style(Style::default().fg(TEXT))
        .block(
            Block::default()
                .title(" Dependencies ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(BORDER)),
        )
        .wrap(Wrap { trim: true });

    frame.render_widget(widget, area);
}

/// Trust dashboard view.
fn render_trust_view(frame: &mut Frame, _state: &AppState, area: Rect) {
    let widget = Paragraph::new("Trust Pipeline Dashboard\n\nPress 'v' to run verification (opsm check)")
        .style(Style::default().fg(TEXT))
        .block(
            Block::default()
                .title(" Trust ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(BORDER)),
        )
        .wrap(Wrap { trim: true });

    frame.render_widget(widget, area);
}

/// Full detail view for a package.
fn render_full_detail(frame: &mut Frame, state: &AppState, area: Rect) {
    let content = if let Some(pkg) = state.selected_package() {
        format!(
            "Package: {}\nVersion: {}\nRegistry: @{}\nInstalled: {}\n\n{}",
            pkg.name,
            pkg.version,
            pkg.forth,
            if pkg.installed { "Yes" } else { "No" },
            pkg.description.as_deref().unwrap_or("No description"),
        )
    } else {
        "No package selected".to_string()
    };

    let widget = Paragraph::new(content)
        .style(Style::default().fg(TEXT))
        .block(
            Block::default()
                .title(" Package Detail [Esc to go back] ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(BORDER)),
        )
        .wrap(Wrap { trim: true });

    frame.render_widget(widget, area);
}

/// Status bar.
fn render_status(frame: &mut Frame, state: &AppState, area: Rect) {
    let mut spans = vec![];

    // Search query display
    if state.input_mode() == InputMode::Search {
        spans.push(Span::styled(" /", Style::default().fg(ACCENT)));
        spans.push(Span::styled(state.search_query(), Style::default().fg(TEXT)));
        spans.push(Span::styled("█", Style::default().fg(ACCENT))); // cursor
    } else if state.input_mode() == InputMode::Confirm {
        spans.push(Span::styled(
            format!(" {} ", state.status_message()),
            Style::default().fg(YELLOW).add_modifier(Modifier::BOLD),
        ));
    } else {
        spans.push(Span::styled(
            format!(" {} ", state.status_message()),
            Style::default().fg(SUBTEXT),
        ));
    }

    let status = Paragraph::new(Line::from(spans))
        .style(Style::default().bg(SURFACE));
    frame.render_widget(status, area);
}

/// Footer with keybindings.
fn render_footer(frame: &mut Frame, state: &AppState, area: Rect) {
    let keys = match state.input_mode() {
        InputMode::Search => "Enter:search  Esc:cancel  Backspace:delete",
        InputMode::Confirm => "y:yes  n/Esc:cancel",
        InputMode::Normal => match state.view() {
            View::Packages | View::Search =>
                "j/k:nav  i:install  r:remove  /:search  1-4:filter  h:history  t:trust  v:verify  ?:help  q:quit",
            View::History =>
                "u:undo  r:redo  Esc:back  q:quit",
            _ =>
                "Esc:back  q:quit",
        },
    };

    let footer = Paragraph::new(Span::styled(
        format!(" {} ", keys),
        Style::default().fg(SUBTEXT),
    )).style(Style::default().bg(SURFACE));

    frame.render_widget(footer, area);
}

// =============================================================================
// Input handling
// =============================================================================

/// Handle a key event. Returns true if the event was consumed.
fn handle_key(state: &mut AppState, key: KeyEvent) {
    // Ctrl+C always quits
    if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
        state.quit();
        return;
    }

    match state.input_mode() {
        InputMode::Search => handle_search_input(state, key),
        InputMode::Confirm => handle_confirm_input(state, key),
        InputMode::Normal => handle_normal_input(state, key),
    }
}

fn handle_search_input(state: &mut AppState, key: KeyEvent) {
    match key.code {
        KeyCode::Esc => state.exit_input_mode(),
        KeyCode::Enter => {
            state.exit_input_mode();
            state.run_search();
        }
        KeyCode::Backspace => state.search_pop(),
        KeyCode::Char(c) => state.search_push(c),
        _ => {}
    }
}

fn handle_confirm_input(state: &mut AppState, key: KeyEvent) {
    match key.code {
        KeyCode::Char('y') | KeyCode::Char('Y') => {
            let action = state.confirm_action().map(|s| s.to_string());
            state.exit_input_mode();
            match action.as_deref() {
                Some("Install") => state.install_selected(),
                Some("Remove") => state.remove_selected(),
                _ => {}
            }
        }
        _ => state.exit_input_mode(),
    }
}

fn handle_normal_input(state: &mut AppState, key: KeyEvent) {
    match key.code {
        // Quit
        KeyCode::Char('q') | KeyCode::Char('Q') => state.quit(),

        // Navigation
        KeyCode::Char('j') | KeyCode::Down => state.cursor_down(),
        KeyCode::Char('k') | KeyCode::Up => state.cursor_up(),
        KeyCode::Char('g') => state.jump_top(),
        KeyCode::Char('G') => state.jump_bottom(),
        KeyCode::PageUp => state.page_up(),
        KeyCode::PageDown => state.page_down(),

        // Search
        KeyCode::Char('/') => state.enter_search(),

        // Filter tabs
        KeyCode::Char('1') => { state.set_filter(Filter::Installed); state.load_installed(); }
        KeyCode::Char('2') => { state.set_filter(Filter::Updates); state.load_installed(); }
        KeyCode::Char('3') => { state.set_filter(Filter::SearchResults); }
        KeyCode::Char('4') => { state.set_filter(Filter::All); state.load_installed(); }

        // Views
        KeyCode::Char('h') => { state.set_view(View::History); state.load_history(); }
        KeyCode::Char('t') => state.set_view(View::Trust),
        KeyCode::Char('d') => state.set_view(View::DepsTree),
        KeyCode::Enter => state.set_view(View::Detail),
        KeyCode::Esc => { state.set_view(View::Packages); state.exit_input_mode(); }

        // Actions
        KeyCode::Char('i') => {
            if let Some(pkg) = state.selected_package() {
                let name = pkg.name.clone();
                state.prompt_confirm("Install", &name);
            }
        }
        KeyCode::Char('r') => {
            if state.view() == View::History {
                state.redo_last();
            } else if let Some(pkg) = state.selected_package() {
                if pkg.installed {
                    let name = pkg.name.clone();
                    state.prompt_confirm("Remove", &name);
                }
            }
        }
        KeyCode::Char('u') => {
            if state.view() == View::History {
                state.undo_last();
            }
        }
        KeyCode::Char('v') => state.run_check(),
        KeyCode::Char('R') => {
            state.load_installed();
            state.set_status("Refreshed".to_string());
        }

        _ => {}
    }
}

// =============================================================================
// Terminal setup/teardown
// =============================================================================

fn setup_terminal() -> io::Result<Terminal<CrosstermBackend<io::Stdout>>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    Terminal::new(backend)
}

fn restore_terminal(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) -> io::Result<()> {
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    Ok(())
}

// =============================================================================
// Main
// =============================================================================

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let mut terminal = setup_terminal()?;

    let size = terminal.size()?;
    let mut state = AppState::new(size.width, size.height);

    // Initial data load
    state.load_installed();

    // Handle CLI flags
    if let Some(query) = cli.search {
        state.enter_search();
        for c in query.chars() {
            state.search_push(c);
        }
        state.exit_input_mode();
        state.run_search();
    }

    // Main event loop — mirrors Ada `while State.Running loop`
    while state.is_running() {
        terminal.draw(|frame| render(frame, &state))?;

        if event::poll(Duration::from_millis(100))? {
            match event::read()? {
                Event::Key(key) => handle_key(&mut state, key),
                Event::Resize(w, h) => state.resize(w, h),
                _ => {}
            }
        }
    }

    restore_terminal(&mut terminal)?;
    Ok(())
}
