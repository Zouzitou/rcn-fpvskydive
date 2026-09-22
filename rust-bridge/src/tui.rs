use std::{
    fs, io,
    process::Command,
    sync::mpsc::{self, Receiver, Sender},
    thread,
    time::Duration,
};

use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{
    Terminal,
    backend::CrosstermBackend,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph, Wrap},
};

use crate::{
    BridgeError, discover_protocol_port, game_check, json_number_field, json_string_field,
    live_verification_valid, mapping_config_path, open_fpv, run_powershell, self_test_gamepad,
    status_path, stop_watch, verify_live_input,
};

const SKY: Color = Color::Rgb(91, 192, 235);
const MINT: Color = Color::Rgb(107, 203, 119);
const AMBER: Color = Color::Rgb(255, 209, 102);
const RED: Color = Color::Rgb(239, 71, 111);
const MUTED: Color = Color::Rgb(135, 151, 169);

#[derive(Clone, Copy, PartialEq, Eq)]
enum Action {
    Launch,
    GameCheck,
    VerifySticks,
    SelfTest,
    Diagnostics,
    Mapping,
    StopBridge,
    Refresh,
    Quit,
}

impl Action {
    const ALL: [Self; 9] = [
        Self::Launch,
        Self::GameCheck,
        Self::VerifySticks,
        Self::SelfTest,
        Self::Diagnostics,
        Self::Mapping,
        Self::StopBridge,
        Self::Refresh,
        Self::Quit,
    ];

    fn label(self) -> &'static str {
        match self {
            Self::Launch => "Launch FPV SkyDive",
            Self::GameCheck => "Verify live game session",
            Self::VerifySticks => "Verify controller sticks",
            Self::SelfTest => "Run Xbox controller self-test",
            Self::Diagnostics => "Open redacted diagnostics",
            Self::Mapping => "Open axis mapping file",
            Self::StopBridge => "Stop current bridge",
            Self::Refresh => "Refresh health snapshot",
            Self::Quit => "Quit console",
        }
    }

    fn hint(self) -> &'static str {
        match self {
            Self::Launch => {
                "Starts the bridge, waits for Xbox readiness, then launches FPV SkyDive."
            }
            Self::GameCheck => "Read-only check for the game, bridge, and virtual Xbox controller.",
            Self::VerifySticks => {
                "Guided four-axis movement check. Close FPV SkyDive before starting it."
            }
            Self::SelfTest => {
                "Creates a temporary neutral Xbox target. Disabled during a live session."
            }
            Self::Diagnostics => "Prints a redacted report in your normal terminal.",
            Self::Mapping => "Opens the editable Mode 2 axis mapping configuration.",
            Self::StopBridge => "Stops the running bridge after confirmation.",
            Self::Refresh => "Refreshes this dashboard without touching the controller.",
            Self::Quit => "Restores the terminal and exits.",
        }
    }
}

struct Snapshot {
    bridge_state: String,
    port: Option<String>,
    mapped_frames: Option<u64>,
    detail: Option<String>,
    verified: bool,
    game_running: bool,
    xbox_present: bool,
}

impl Snapshot {
    fn initial() -> Self {
        let status = fs::read_to_string(status_path())
            .unwrap_or_else(|_| "{\"state\":\"not_started\"}".to_string());
        let port = json_string_field(&status, "port");
        Self {
            bridge_state: json_string_field(&status, "state")
                .unwrap_or_else(|| "unknown".to_string()),
            verified: port.as_deref().is_some_and(live_verification_valid),
            port,
            mapped_frames: json_number_field(&status, "mapped_frames"),
            detail: json_string_field(&status, "detail"),
            game_running: false,
            xbox_present: false,
        }
    }

    fn collect() -> Self {
        let status = fs::read_to_string(status_path())
            .unwrap_or_else(|_| "{\"state\":\"not_started\"}".to_string());
        let port = json_string_field(&status, "port");
        let bridge_state =
            json_string_field(&status, "state").unwrap_or_else(|| "unknown".to_string());
        let verified = port.as_deref().is_some_and(live_verification_valid);
        let game_running = powershell_bool(
            "[bool](Get-Process -Name 'FPV.SkyDive' -ErrorAction SilentlyContinue | Select-Object -First 1)",
        );
        let xbox_present = powershell_bool(
            "[bool](Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' -and ($_.Class -eq 'XnaComposite' -or $_.FriendlyName -match 'Xbox 360 (Controller|kontroll) for Windows|Xbox 360-kontroll för Windows') } | Select-Object -First 1)",
        );
        Self {
            bridge_state,
            port,
            mapped_frames: json_number_field(&status, "mapped_frames"),
            detail: json_string_field(&status, "detail"),
            verified,
            game_running,
            xbox_present,
        }
    }

    fn readiness(&self) -> (&'static str, Color, &'static str) {
        if self.game_running && self.bridge_state == "connected" && self.xbox_present {
            (
                "FLYING READY",
                MINT,
                "Game, bridge, and Xbox target are active.",
            )
        } else if self.bridge_state == "connected" && self.xbox_present {
            (
                "BRIDGE READY",
                SKY,
                "Xbox target is connected; launch the game when ready.",
            )
        } else if !self.verified {
            (
                "VERIFY STICKS",
                AMBER,
                "Move all four sticks once before the bridge can start.",
            )
        } else {
            (
                "WAITING",
                AMBER,
                "Open the controller or refresh after connecting it.",
            )
        }
    }
}

fn powershell_bool(script: &str) -> bool {
    run_powershell(script)
        .ok()
        .filter(|output| output.status.success())
        .map(|output| {
            String::from_utf8_lossy(&output.stdout)
                .trim()
                .eq_ignore_ascii_case("true")
        })
        .unwrap_or(false)
}

struct App {
    snapshot: Snapshot,
    selected: usize,
    notice: String,
    confirm_stop: bool,
    refresh_request: Sender<()>,
    refreshes: Receiver<Snapshot>,
}

impl App {
    fn new() -> Self {
        let (refresh_request, requests) = mpsc::channel();
        let (snapshots, refreshes) = mpsc::channel();
        thread::spawn(move || {
            loop {
                let _ = requests.recv_timeout(Duration::from_secs(3));
                if snapshots.send(Snapshot::collect()).is_err() {
                    break;
                }
            }
        });
        let _ = refresh_request.send(());
        Self {
            snapshot: Snapshot::initial(),
            selected: 0,
            notice: "Use ↑/↓ or j/k, then Enter. Checking game and controller status…".to_string(),
            confirm_stop: false,
            refresh_request,
            refreshes,
        }
    }

    fn action(&self) -> Action {
        Action::ALL[self.selected]
    }

    fn enabled(&self, action: Action) -> bool {
        match action {
            Action::Launch => !self.snapshot.game_running,
            Action::GameCheck => self.snapshot.game_running,
            Action::VerifySticks => !self.snapshot.game_running,
            Action::SelfTest => {
                !self.snapshot.game_running && self.snapshot.bridge_state != "connected"
            }
            Action::StopBridge => self.snapshot.bridge_state == "connected",
            _ => true,
        }
    }

    fn move_selection(&mut self, delta: isize) {
        let len = Action::ALL.len() as isize;
        self.selected = (self.selected as isize + delta).rem_euclid(len) as usize;
    }

    fn refresh(&mut self) {
        let _ = self.refresh_request.send(());
        self.notice = "Refreshing game and controller status…".to_string();
    }

    fn apply_pending_refresh(&mut self) {
        let mut updated = false;
        while let Ok(snapshot) = self.refreshes.try_recv() {
            self.snapshot = snapshot;
            updated = true;
        }
        if updated && self.notice == "Refreshing game and controller status…" {
            self.notice = "Status refreshed. No controller state was changed.".to_string();
        }
    }
}

pub(crate) fn run() -> Result<(), BridgeError> {
    let mut terminal = init_terminal()?;
    let mut app = App::new();
    let result = event_loop(&mut terminal, &mut app);
    restore_terminal(&mut terminal)?;
    result
}

type UiTerminal = Terminal<CrosstermBackend<io::Stdout>>;

fn init_terminal() -> Result<UiTerminal, BridgeError> {
    enable_raw_mode().map_err(io_error)?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture).map_err(io_error)?;
    Terminal::new(CrosstermBackend::new(stdout)).map_err(io_error)
}

fn restore_terminal(terminal: &mut UiTerminal) -> Result<(), BridgeError> {
    disable_raw_mode().map_err(io_error)?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )
    .map_err(io_error)?;
    terminal.show_cursor().map_err(io_error)
}

fn io_error(error: io::Error) -> BridgeError {
    BridgeError::Io(error)
}

fn event_loop(terminal: &mut UiTerminal, app: &mut App) -> Result<(), BridgeError> {
    loop {
        app.apply_pending_refresh();
        terminal.draw(|frame| draw(frame, app)).map_err(io_error)?;
        if !event::poll(Duration::from_millis(250)).map_err(io_error)? {
            continue;
        }
        let Event::Key(key) = event::read().map_err(io_error)? else {
            continue;
        };
        if key.kind != KeyEventKind::Press {
            continue;
        }
        if app.confirm_stop {
            match key.code {
                KeyCode::Char('y') | KeyCode::Enter => {
                    app.confirm_stop = false;
                    run_action(terminal, app, Action::StopBridge)?;
                }
                KeyCode::Char('n') | KeyCode::Esc => {
                    app.confirm_stop = false;
                    app.notice = "Stop cancelled. The bridge was not changed.".to_string();
                }
                _ => {}
            }
            continue;
        }
        match key.code {
            KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
            KeyCode::Up | KeyCode::Char('k') => app.move_selection(-1),
            KeyCode::Down | KeyCode::Char('j') => app.move_selection(1),
            KeyCode::Char('r') => app.refresh(),
            KeyCode::Char('l') => run_shortcut(terminal, app, Action::Launch)?,
            KeyCode::Char('g') => run_shortcut(terminal, app, Action::GameCheck)?,
            KeyCode::Char('v') => run_shortcut(terminal, app, Action::VerifySticks)?,
            KeyCode::Char('d') => run_shortcut(terminal, app, Action::Diagnostics)?,
            KeyCode::Char('m') => run_shortcut(terminal, app, Action::Mapping)?,
            KeyCode::Enter => {
                let action = app.action();
                if action == Action::Quit {
                    return Ok(());
                }
                if action == Action::StopBridge {
                    if app.enabled(action) {
                        app.confirm_stop = true;
                    } else {
                        app.notice = "There is no connected bridge to stop.".to_string();
                    }
                } else if app.enabled(action) {
                    run_action(terminal, app, action)?;
                } else {
                    app.notice =
                        format!("{} is unavailable in the current session.", action.label());
                }
            }
            _ => {}
        }
    }
}

fn run_shortcut(
    terminal: &mut UiTerminal,
    app: &mut App,
    action: Action,
) -> Result<(), BridgeError> {
    if app.enabled(action) {
        run_action(terminal, app, action)
    } else {
        app.notice = format!("{} is unavailable in the current session.", action.label());
        Ok(())
    }
}

fn run_action(terminal: &mut UiTerminal, app: &mut App, action: Action) -> Result<(), BridgeError> {
    restore_terminal(terminal)?;
    println!("\nRCN FPV SkyDive › {}\n", action.label());
    let result = match action {
        Action::Launch => open_fpv(),
        Action::GameCheck => game_check(),
        Action::VerifySticks => {
            let stop_result = if app.snapshot.bridge_state == "connected" {
                println!("The game is closed; clearing its bridge session first...");
                stop_watch()
            } else {
                Ok(())
            };
            stop_result.and_then(|_| {
                discover_protocol_port()
                    .ok_or(BridgeError::NoProtocolPort)
                    .and_then(|port| verify_live_input(&port))
            })
        }
        Action::SelfTest => self_test_gamepad(),
        Action::Diagnostics => crate::diagnose(true),
        Action::Mapping => Command::new("notepad.exe")
            .arg(mapping_config_path())
            .spawn()
            .map(|_| ())
            .map_err(BridgeError::Io),
        Action::StopBridge => stop_watch(),
        Action::Refresh | Action::Quit => Ok(()),
    };
    match &result {
        Ok(()) => println!("\n✓ Completed safely."),
        Err(error) => eprintln!("\n! {error}"),
    }
    println!("\nPress any key to return to the Flight Console...");
    wait_for_key()?;
    *terminal = init_terminal()?;
    app.refresh();
    app.notice = match &result {
        Ok(()) => format!("{} completed.", action.label()),
        Err(error) => format!("{} failed: {error}", action.label()),
    };
    Ok(())
}

fn wait_for_key() -> Result<(), BridgeError> {
    enable_raw_mode().map_err(io_error)?;
    let result = (|| loop {
        let Event::Key(key) = event::read().map_err(io_error)? else {
            continue;
        };
        if key.kind == KeyEventKind::Press {
            break Ok(());
        }
    })();
    let restore_result = disable_raw_mode().map_err(io_error);
    result.and(restore_result)
}

fn draw(frame: &mut ratatui::Frame, app: &App) {
    let area = frame.area();
    if area.width < 76 || area.height < 24 {
        frame.render_widget(
            Paragraph::new("Make this terminal at least 76×24, then press r.")
                .style(Style::default().fg(AMBER))
                .alignment(Alignment::Center)
                .block(Block::bordered().title(" RCN FPV SkyDive ")),
            area,
        );
        return;
    }
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Length(8),
            Constraint::Min(10),
            Constraint::Length(3),
        ])
        .split(area);
    draw_header(frame, rows[0], app);
    draw_health(frame, rows[1], app);
    draw_main(frame, rows[2], app);
    draw_footer(frame, rows[3], app);
    if app.confirm_stop {
        draw_stop_confirmation(frame, area);
    }
}

fn draw_header(frame: &mut ratatui::Frame, area: Rect, app: &App) {
    let (label, color, detail) = app.snapshot.readiness();
    let columns = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Min(42), Constraint::Length(18)])
        .split(area);
    let text = Line::from(vec![
        Span::styled(
            " RCN FPV SKYDIVE ",
            Style::default().fg(SKY).add_modifier(Modifier::BOLD),
        ),
        Span::styled("  /  Controller Flight Console", Style::default().fg(MUTED)),
    ]);
    frame.render_widget(
        Paragraph::new(vec![
            text,
            Line::from(Span::styled(
                format!(" {detail}"),
                Style::default().fg(MUTED),
            )),
        ])
        .block(
            Block::default()
                .borders(Borders::BOTTOM)
                .border_style(Style::default().fg(SKY)),
        ),
        columns[0],
    );
    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(
            format!(" {label} "),
            Style::default()
                .fg(Color::Black)
                .bg(color)
                .add_modifier(Modifier::BOLD),
        )))
        .alignment(Alignment::Right)
        .block(
            Block::default()
                .borders(Borders::BOTTOM)
                .border_style(Style::default().fg(SKY)),
        ),
        columns[1],
    );
}

fn draw_health(frame: &mut ratatui::Frame, area: Rect, app: &App) {
    let cards = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(25),
            Constraint::Percentage(25),
            Constraint::Percentage(25),
            Constraint::Percentage(25),
        ])
        .split(area);
    card(
        frame,
        cards[0],
        "BRIDGE",
        &app.snapshot.bridge_state.to_uppercase(),
        state_color(&app.snapshot.bridge_state),
        app.snapshot.port.as_deref().unwrap_or("No Protocol port"),
    );
    card(
        frame,
        cards[1],
        "CONTROLLER",
        if app.snapshot.verified {
            "VERIFIED"
        } else {
            "NEEDS CHECK"
        },
        if app.snapshot.verified { MINT } else { AMBER },
        "Four-axis live approval",
    );
    card(
        frame,
        cards[2],
        "VIRTUAL XBOX",
        if app.snapshot.xbox_present {
            "PRESENT"
        } else {
            "OFFLINE"
        },
        if app.snapshot.xbox_present {
            MINT
        } else {
            MUTED
        },
        "Windows virtual target",
    );
    let game_detail = app
        .snapshot
        .mapped_frames
        .map(|frames| format!("{frames} mapped frames"))
        .unwrap_or_else(|| "Launch after bridge is ready".to_string());
    card(
        frame,
        cards[3],
        "FPV SKYDIVE",
        if app.snapshot.game_running {
            "RUNNING"
        } else {
            "NOT RUNNING"
        },
        if app.snapshot.game_running {
            MINT
        } else {
            MUTED
        },
        &game_detail,
    );
}

fn card(
    frame: &mut ratatui::Frame,
    area: Rect,
    title: &str,
    value: &str,
    color: Color,
    detail: &str,
) {
    frame.render_widget(
        Paragraph::new(vec![
            Line::from(Span::styled(
                value,
                Style::default().fg(color).add_modifier(Modifier::BOLD),
            )),
            Line::from(Span::styled(detail, Style::default().fg(MUTED))),
        ])
        .block(
            Block::bordered()
                .title(Span::styled(
                    format!(" {title} "),
                    Style::default().fg(MUTED),
                ))
                .border_style(Style::default().fg(Color::Rgb(57, 71, 89))),
        )
        .wrap(Wrap { trim: true }),
        area,
    );
}

fn draw_main(frame: &mut ratatui::Frame, area: Rect, app: &App) {
    let columns = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(43), Constraint::Percentage(57)])
        .split(area);
    let items = Action::ALL
        .iter()
        .map(|action| {
            let enabled = app.enabled(*action);
            let prefix = if enabled { "  " } else { "  • " };
            ListItem::new(Line::from(Span::styled(
                format!("{prefix}{}", action.label()),
                Style::default().fg(if enabled { Color::White } else { MUTED }),
            )))
        })
        .collect::<Vec<_>>();
    let list = List::new(items)
        .block(
            Block::bordered()
                .title(Span::styled(
                    " ACTIONS ",
                    Style::default().fg(SKY).add_modifier(Modifier::BOLD),
                ))
                .border_style(Style::default().fg(SKY)),
        )
        .highlight_style(
            Style::default()
                .fg(Color::Black)
                .bg(SKY)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("› ");
    let mut state = ListState::default();
    state.select(Some(app.selected));
    frame.render_stateful_widget(list, columns[0], &mut state);

    let action = app.action();
    let status_note = app
        .snapshot
        .detail
        .as_deref()
        .unwrap_or("No active warning.");
    let lines = vec![
        Line::from(Span::styled(
            action.label(),
            Style::default().fg(SKY).add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(Span::styled(
            action.hint(),
            Style::default().fg(Color::White),
        )),
        Line::from(""),
        Line::from(vec![
            Span::styled("Session note: ", Style::default().fg(MUTED)),
            Span::styled(
                status_note,
                Style::default().fg(if app.snapshot.detail.is_some() {
                    AMBER
                } else {
                    MINT
                }),
            ),
        ]),
        Line::from(""),
        Line::from(Span::styled(
            if app.enabled(action) {
                "Press Enter to continue."
            } else {
                "Unavailable until the session state changes."
            },
            Style::default().fg(if app.enabled(action) { MINT } else { AMBER }),
        )),
    ];
    frame.render_widget(
        Paragraph::new(lines)
            .block(
                Block::bordered()
                    .title(Span::styled(
                        " DETAILS ",
                        Style::default().fg(SKY).add_modifier(Modifier::BOLD),
                    ))
                    .border_style(Style::default().fg(Color::Rgb(57, 71, 89))),
            )
            .wrap(Wrap { trim: true }),
        columns[1],
    );
}

fn draw_footer(frame: &mut ratatui::Frame, area: Rect, app: &App) {
    frame.render_widget(
        Paragraph::new(vec![
            Line::from(Span::styled(&app.notice, Style::default().fg(Color::White))),
            Line::from(Span::styled(
                "↑/↓ j/k select · Enter choose · l launch · g check · r refresh · q quit",
                Style::default().fg(MUTED),
            )),
        ])
        .block(
            Block::default()
                .borders(Borders::TOP)
                .border_style(Style::default().fg(Color::Rgb(57, 71, 89))),
        )
        .wrap(Wrap { trim: true }),
        area,
    );
}

fn draw_stop_confirmation(frame: &mut ratatui::Frame, area: Rect) {
    let popup = centered_rect(62, 34, area);
    frame.render_widget(Clear, popup);
    frame.render_widget(
        Paragraph::new(vec![
            Line::from(Span::styled(
                "Stop the bridge?",
                Style::default().fg(RED).add_modifier(Modifier::BOLD),
            )),
            Line::from(""),
            Line::from("This removes the virtual controller until the next game launch."),
            Line::from(""),
            Line::from(Span::styled(
                "Enter / y  Stop bridge     Esc / n  Keep running",
                Style::default().fg(AMBER),
            )),
        ])
        .alignment(Alignment::Center)
        .block(
            Block::bordered()
                .title(" CONFIRM STOP ")
                .border_style(Style::default().fg(RED)),
        )
        .wrap(Wrap { trim: true }),
        popup,
    );
}

fn centered_rect(width_percent: u16, height_percent: u16, area: Rect) -> Rect {
    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - height_percent) / 2),
            Constraint::Percentage(height_percent),
            Constraint::Percentage((100 - height_percent) / 2),
        ])
        .split(area);
    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - width_percent) / 2),
            Constraint::Percentage(width_percent),
            Constraint::Percentage((100 - width_percent) / 2),
        ])
        .split(vertical[1])[1]
}

fn state_color(state: &str) -> Color {
    match state {
        "connected" => MINT,
        "awaiting_live_verification" | "waiting_for_controller" => AMBER,
        "failed" => RED,
        _ => MUTED,
    }
}
