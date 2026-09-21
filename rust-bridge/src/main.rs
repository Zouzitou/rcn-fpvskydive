mod mapping;
mod protocol;

use mapping::{MappingConfig, mode2_with_config};
use protocol::{drain_frames, enable_simulator, parse_sticks, read_sticks};
use std::{
    env, fs,
    io::{Read, Write},
    path::PathBuf,
    process::Command,
    thread,
    time::{Duration, Instant},
};
use thiserror::Error;
use vigem_rust::{Client, ClientError, X360Report};
use windows::Win32::Foundation::{CloseHandle, ERROR_ALREADY_EXISTS, GetLastError, HANDLE};
use windows::Win32::System::Threading::CreateMutexW;
use windows::core::w;

#[derive(Debug, Error)]
enum BridgeError {
    #[error(
        "usage: rcn-bridge status | diagnose [--redact] | start | stop | repair | uninstall | self-test | watch | bridge-auto | probe --port COM12 | bridge --port COM12 | bridge-smoke --port COM12"
    )]
    Usage,
    #[error("no healthy DJI Protocol serial interface was found")]
    NoProtocolPort,
    #[error("no checksum-validated live stick frames were received")]
    NoLiveFrames,
    #[error("the RCN bridge is already running")]
    AlreadyRunning,
    #[error("serial error: {0}")]
    Serial(#[from] serialport::Error),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("ViGEm error: {0}")]
    Vigem(#[from] ClientError),
}

fn status_path() -> PathBuf {
    let root = env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    root.join("RCN-FPVSkyDive")
        .join("state")
        .join("bridge.json")
}

fn app_root() -> PathBuf {
    env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
        .join("RCN-FPVSkyDive")
}

fn mapping_config_path() -> PathBuf {
    app_root().join("state").join("mapping.conf")
}

fn log_line(message: &str) {
    let path = app_root().join("logs").join("bridge.log");
    let Some(parent) = path.parent() else { return };
    if fs::create_dir_all(parent).is_err() {
        return;
    }
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|time| time.as_secs())
        .unwrap_or(0);
    if let Ok(mut file) = fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{now} {message}");
    }
}

fn escape_json(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn publish_status(state: &str, port: Option<&str>, mapped_frames: usize, detail: Option<&str>) {
    let path = status_path();
    let Some(parent) = path.parent() else { return };
    if fs::create_dir_all(parent).is_err() {
        return;
    }
    let port = port
        .map(|port| format!("\"{}\"", escape_json(port)))
        .unwrap_or_else(|| "null".to_string());
    let detail = detail
        .map(|detail| format!("\"{}\"", escape_json(detail)))
        .unwrap_or_else(|| "null".to_string());
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|time| time.as_secs())
        .unwrap_or(0);
    let json = format!(
        "{{\"state\":\"{}\",\"port\":{},\"mapped_frames\":{},\"detail\":{},\"updated_unix\":{}}}",
        escape_json(state),
        port,
        mapped_frames,
        detail,
        timestamp
    );
    let _ = fs::write(path, json);
    log_line(&format!("state={state} mapped_frames={mapped_frames}"));
}

fn print_status() {
    let status = fs::read_to_string(status_path())
        .unwrap_or_else(|_| "{\"state\":\"not_started\"}".to_string());
    println!("{status}");
}

fn run_powershell(script: &str) -> Result<std::process::Output, BridgeError> {
    Ok(Command::new("powershell.exe")
        .args(["-NoProfile", "-NonInteractive", "-Command", script])
        .output()?)
}

fn output_text(output: std::process::Output) -> String {
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

fn redact_text(value: &str) -> String {
    let mut redacted = value.to_string();
    for (variable, token) in [
        ("LOCALAPPDATA", "%LOCALAPPDATA%"),
        ("APPDATA", "%APPDATA%"),
        ("USERPROFILE", "%USERPROFILE%"),
    ] {
        if let Some(path) = env::var_os(variable) {
            let path = path.to_string_lossy();
            if !path.is_empty() {
                redacted = redacted.replace(path.as_ref(), token);
            }
        }
    }
    redacted
}

fn read_tail(path: &std::path::Path, count: usize) -> Vec<String> {
    let Ok(contents) = fs::read_to_string(path) else {
        return Vec::new();
    };
    let lines: Vec<_> = contents.lines().map(str::to_string).collect();
    lines
        .into_iter()
        .rev()
        .take(count)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect()
}

struct WatchMutex(HANDLE);

impl Drop for WatchMutex {
    fn drop(&mut self) {
        let _ = unsafe { CloseHandle(self.0) };
    }
}

fn acquire_watch_mutex() -> Result<WatchMutex, BridgeError> {
    let handle = unsafe { CreateMutexW(None, true, w!("Global\\RCN-FPVSkyDive-Bridge")) }
        .map_err(|error| BridgeError::Io(std::io::Error::other(error.to_string())))?;
    if unsafe { GetLastError() }.0 == ERROR_ALREADY_EXISTS.0 {
        drop(WatchMutex(handle));
        return Err(BridgeError::AlreadyRunning);
    }
    Ok(WatchMutex(handle))
}

fn diagnose(redact: bool) -> Result<(), BridgeError> {
    let status = fs::read_to_string(status_path())
        .unwrap_or_else(|_| "{\"state\":\"not_started\"}".to_string());
    let interfaces_output = run_powershell(
        "Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPDeviceID -match 'VID_2CA3' -or $_.Name -match 'DJI USB' } | ForEach-Object { \"$($_.Status)|$($_.Name)|$($_.PNPDeviceID)\" }",
    )?;
    let os_output = run_powershell(
        "Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,OSArchitecture | ConvertTo-Json -Compress",
    )?;
    let driver_output = run_powershell(
        "Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID -match 'VID_2CA3' } | ForEach-Object { \"$($_.DeviceName)|$($_.DriverProviderName)|$($_.DriverVersion)|$($_.InfName)|signed=$($_.IsSigned)\" }",
    )?;
    let steam_output = run_powershell(
        "$roots=@(); $steam=(Get-ItemProperty 'HKCU:\\Software\\Valve\\Steam' -ErrorAction SilentlyContinue).SteamPath; if($steam){$roots+=$steam; $vdf=Join-Path $steam 'steamapps\\libraryfolders.vdf'; if(Test-Path $vdf){$roots += [regex]::Matches((Get-Content $vdf -Raw),'\"path\"\\s+\"([^\"]+)\"') | ForEach-Object {$_.Groups[1].Value}}}; $roots | Select-Object -Unique | ForEach-Object { $p=Join-Path $_ 'steamapps\\common\\FPV SkyDive'; if(Test-Path $p){$p} }",
    )?;
    let startup = fs::read_to_string(app_root().join("state").join("startup.json"))
        .unwrap_or_else(|_| "not_registered".to_string());
    let protocol_port = discover_protocol_port();
    let live_frames = protocol_port.as_deref().map(probe_live_frames).transpose();
    let processes_output = run_powershell(
        "Get-Process -Name rcn-bridge -ErrorAction SilentlyContinue | ForEach-Object { \"pid=$($_.Id)|path=$($_.Path)\" }",
    )?;
    let log_path = app_root().join("logs").join("bridge.log");
    println!(
        "status: {}",
        if redact { redact_text(&status) } else { status }
    );
    println!("runtime: native-rust {}", env!("CARGO_PKG_VERSION"));
    let windows = output_text(os_output);
    println!(
        "windows: {}",
        if redact {
            redact_text(&windows)
        } else {
            windows
        }
    );
    println!("interfaces:");
    let interfaces = String::from_utf8_lossy(&interfaces_output.stdout).to_string();
    let interfaces = if redact {
        redact_text(&interfaces)
    } else {
        interfaces
    };
    if interfaces.trim().is_empty() {
        println!("  none");
    } else {
        for line in interfaces.lines() {
            println!("  {line}");
        }
    }
    println!("driver records:");
    let drivers = output_text(driver_output);
    let drivers = if redact {
        redact_text(&drivers)
    } else {
        drivers
    };
    if drivers.is_empty() {
        println!("  none");
    } else {
        for line in drivers.lines() {
            println!("  {line}");
        }
    }
    println!(
        "protocol port: {}",
        protocol_port.as_deref().unwrap_or("none")
    );
    let live_frame_text = match live_frames {
        Ok(Some(count)) => count.to_string(),
        Ok(None) => "not attempted".to_string(),
        Err(error) => format!("error: {error}"),
    };
    println!("live frames: {live_frame_text}");
    println!(
        "startup: {}",
        if redact {
            redact_text(&startup)
        } else {
            startup
        }
    );
    let game_path = {
        let text = output_text(steam_output);
        if text.is_empty() {
            "not detected".to_string()
        } else {
            text
        }
    };
    println!(
        "fpv skydive: {}",
        if redact {
            redact_text(&game_path)
        } else {
            game_path
        }
    );
    println!("bridge processes:");
    let processes = output_text(processes_output);
    let processes = if redact {
        redact_text(&processes)
    } else {
        processes
    };
    if processes.is_empty() {
        println!("  none");
    } else {
        for line in processes.lines() {
            println!("  {line}");
        }
    }
    let mapping_path = mapping_config_path().display().to_string();
    let log_path_display = log_path.display().to_string();
    println!(
        "mapping: {}",
        if redact {
            redact_text(&mapping_path)
        } else {
            mapping_path
        }
    );
    println!(
        "log: {}",
        if redact {
            redact_text(&log_path_display)
        } else {
            log_path_display
        }
    );
    println!("last log lines:");
    for line in read_tail(&log_path, 100) {
        println!("  {}", if redact { redact_text(&line) } else { line });
    }
    Ok(())
}

fn start_watch() -> Result<(), BridgeError> {
    let executable = env::current_exe()?;
    let mut child = Command::new(executable).arg("watch").spawn()?;
    thread::sleep(Duration::from_millis(250));
    if let Some(status) = child.try_wait()? {
        if !status.success() {
            return Err(BridgeError::AlreadyRunning);
        }
    }
    println!("{{\"started\":true,\"pid\":{}}}", child.id());
    Ok(())
}

fn stop_watch() -> Result<(), BridgeError> {
    let path = env::current_exe()?
        .display()
        .to_string()
        .replace('\'', "''");
    let script = format!(
        "Get-CimInstance Win32_Process -Filter \"Name = 'rcn-bridge.exe'\" | Where-Object {{ $_.ExecutablePath -eq '{path}' -and $_.CommandLine -like '* watch*' }} | ForEach-Object {{ Stop-Process -Id $_.ProcessId -Force }}"
    );
    let output = run_powershell(&script)?;
    if !output.status.success() {
        return Err(BridgeError::Io(std::io::Error::other(
            String::from_utf8_lossy(&output.stderr).trim(),
        )));
    }
    publish_status("stopped", None, 0, Some("manual stop"));
    println!("{{\"stopped\":true}}");
    Ok(())
}

fn repair() -> Result<(), BridgeError> {
    let output = Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
        .arg(app_root().join("startup.ps1"))
        .args(["-Action", "install"])
        .output()?;
    std::io::stdout().write_all(&output.stdout)?;
    std::io::stderr().write_all(&output.stderr)?;
    if !output.status.success() {
        return Err(BridgeError::Io(std::io::Error::other(
            "repair script failed",
        )));
    }
    Ok(())
}

fn uninstall() -> Result<(), BridgeError> {
    let output = Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
        .arg(app_root().join("uninstall.ps1"))
        .output()?;
    std::io::stdout().write_all(&output.stdout)?;
    std::io::stderr().write_all(&output.stderr)?;
    if !output.status.success() {
        return Err(BridgeError::Io(std::io::Error::other(
            "uninstall script failed",
        )));
    }
    Ok(())
}

fn port_from_args() -> Result<String, BridgeError> {
    let mut args = env::args().skip(1);
    let _command = args.next().ok_or(BridgeError::Usage)?;
    if args.next().as_deref() != Some("--port") {
        return Err(BridgeError::Usage);
    }
    args.next().ok_or(BridgeError::Usage)
}

fn connect(port: &str) -> Result<Box<dyn serialport::SerialPort>, BridgeError> {
    let mut serial = serialport::new(port, 115_200)
        .timeout(Duration::from_millis(80))
        .open()?;
    serial.write_all(&enable_simulator())?;
    Ok(serial)
}

fn probe_live_frames(port: &str) -> Result<usize, BridgeError> {
    let mut serial = connect(port)?;
    let mut buffer = Vec::new();
    let mut chunk = [0u8; 4096];
    for _ in 0..12 {
        serial.write_all(&read_sticks())?;
        thread::sleep(Duration::from_millis(60));
        if let Ok(count) = serial.read(&mut chunk) {
            buffer.extend_from_slice(&chunk[..count]);
        }
    }
    Ok(drain_frames(&mut buffer)
        .iter()
        .filter(|frame| parse_sticks(frame).is_ok())
        .count())
}

fn discover_protocol_port() -> Option<String> {
    let query = "Get-CimInstance Win32_PnPEntity | Where-Object { $_.Status -eq 'OK' -and $_.PNPDeviceID -match 'VID_2CA3' -and $_.Name -match 'For Protocol.*\\(COM[0-9]+\\)' } | Sort-Object Name | Select-Object -First 1 -ExpandProperty Name";
    let output = Command::new("powershell.exe")
        .args(["-NoProfile", "-NonInteractive", "-Command", query])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let name = String::from_utf8_lossy(&output.stdout);
    let start = name.find("(COM")? + 1;
    let end = name[start..].find(')')? + start;
    let port = name[start..end].trim();
    port.starts_with("COM").then(|| port.to_string())
}

fn self_test_gamepad() -> Result<(), BridgeError> {
    let client = Client::connect()?;
    let target = client.new_x360_target().plug()?.wait_for_ready()?;
    let pulse = X360Report {
        thumb_lx: 4_096,
        ..Default::default()
    };
    target.update(&pulse)?;
    target.update(&X360Report::default())?;
    println!("{{\"virtual_gamepad_test\":\"passed\",\"cleanup\":\"neutral update sent\"}}");
    Ok(())
}

fn run_bridge(
    port: &str,
    duration: Option<Duration>,
    mapping: MappingConfig,
) -> Result<usize, BridgeError> {
    publish_status("connecting", Some(port), 0, None);
    let mut serial = connect(port)?;
    let deadline = duration.map(|duration| Instant::now() + duration);
    let mut buffer = Vec::new();
    let mut chunk = [0u8; 4096];
    let validation_deadline = Instant::now() + Duration::from_secs(3);
    let mut validated_frames = 0;
    while validated_frames < 3 && Instant::now() < validation_deadline {
        serial.write_all(&read_sticks())?;
        if let Ok(count) = serial.read(&mut chunk) {
            buffer.extend_from_slice(&chunk[..count]);
        }
        validated_frames += drain_frames(&mut buffer)
            .iter()
            .filter_map(|packet| parse_sticks(packet).ok())
            .count();
        thread::sleep(Duration::from_millis(20));
    }
    if validated_frames < 3 {
        publish_status("no_live_input", Some(port), 0, None);
        return Err(BridgeError::NoLiveFrames);
    }
    let client = Client::connect()?;
    let target = client.new_x360_target().plug()?.wait_for_ready()?;
    let neutral = X360Report::default();
    target.update(&neutral)?;
    let mut mapped_frames = 0;
    let mut last_status = Instant::now();
    loop {
        serial.write_all(&read_sticks())?;
        if let Ok(count) = serial.read(&mut chunk) {
            buffer.extend_from_slice(&chunk[..count]);
        }
        for packet in drain_frames(&mut buffer) {
            if let Ok(frame) = parse_sticks(&packet) {
                let axes = mode2_with_config(frame, mapping);
                let report = X360Report {
                    thumb_lx: axes.left_x,
                    thumb_ly: axes.left_y,
                    thumb_rx: axes.right_x,
                    thumb_ry: axes.right_y,
                    ..Default::default()
                };
                target.update(&report)?;
                mapped_frames += 1;
            }
        }
        if last_status.elapsed() >= Duration::from_secs(1) {
            publish_status("connected", Some(port), mapped_frames, None);
            last_status = Instant::now();
        }
        if deadline.is_some_and(|time| Instant::now() >= time) {
            target.update(&neutral)?;
            if mapped_frames == 0 {
                publish_status("no_live_input", Some(port), 0, None);
                return Err(BridgeError::NoLiveFrames);
            }
            publish_status(
                "stopped",
                Some(port),
                mapped_frames,
                Some("smoke test completed"),
            );
            return Ok(mapped_frames);
        }
        thread::sleep(Duration::from_millis(20));
    }
}

fn watch() -> Result<(), BridgeError> {
    let _watch_mutex = match acquire_watch_mutex() {
        Ok(mutex) => mutex,
        Err(BridgeError::AlreadyRunning) => {
            publish_status(
                "already_running",
                None,
                0,
                Some("duplicate watcher prevented"),
            );
            return Err(BridgeError::AlreadyRunning);
        }
        Err(error) => return Err(error),
    };
    let mapping = MappingConfig::load(&mapping_config_path());
    loop {
        match discover_protocol_port() {
            Some(port) => {
                publish_status("connecting", Some(&port), 0, None);
                eprintln!("RCN bridge: using {port}");
                if let Err(error) = run_bridge(&port, None, mapping) {
                    publish_status("waiting_for_controller", None, 0, Some(&error.to_string()));
                    eprintln!("RCN bridge: disconnected or unavailable: {error}");
                }
            }
            None => {
                publish_status("waiting_for_controller", None, 0, None);
                eprintln!("RCN bridge: waiting for a healthy DJI Protocol interface");
            }
        }
        thread::sleep(Duration::from_secs(1));
    }
}

fn main() -> Result<(), BridgeError> {
    let command = env::args().nth(1).ok_or(BridgeError::Usage)?;
    if command == "status" {
        print_status();
        return Ok(());
    }
    if command == "diagnose" {
        return diagnose(env::args().nth(2).as_deref() == Some("--redact"));
    }
    if command == "start" {
        return start_watch();
    }
    if command == "stop" {
        return stop_watch();
    }
    if command == "repair" {
        return repair();
    }
    if command == "uninstall" {
        return uninstall();
    }
    if command == "self-test" {
        return self_test_gamepad();
    }
    if command == "watch" {
        return watch();
    }
    if command == "bridge-auto" {
        let port = discover_protocol_port().ok_or(BridgeError::NoProtocolPort)?;
        run_bridge(&port, None, MappingConfig::load(&mapping_config_path()))?;
        return Ok(());
    }
    let port = port_from_args()?;
    if command == "probe" {
        let sticks = probe_live_frames(&port)?;
        println!(
            "{{\"protocol_port\":\"{}\",\"valid_stick_frames\":{}}}",
            port, sticks
        );
        return Ok(());
    }
    if command != "bridge" && command != "bridge-smoke" {
        return Err(BridgeError::Usage);
    }
    let mapped_frames = run_bridge(
        &port,
        (command == "bridge-smoke").then(|| Duration::from_secs(2)),
        MappingConfig::load(&mapping_config_path()),
    )?;
    if command == "bridge-smoke" {
        println!(
            "{{\"bridge_smoke\":\"passed\",\"mapped_frames\":{mapped_frames},\"cleanup\":\"neutral update sent\"}}"
        );
    }
    Ok(())
}

#[cfg(test)]
mod status_tests {
    use super::{BridgeError, acquire_watch_mutex, escape_json, redact_text};

    #[test]
    fn escapes_status_text_for_json() {
        assert_eq!(escape_json("COM12 \"busy\""), "COM12 \\\"busy\\\"");
    }

    #[test]
    fn rejects_a_second_watcher_owner() {
        let first = acquire_watch_mutex().expect("first watcher owner");
        assert!(matches!(
            acquire_watch_mutex(),
            Err(BridgeError::AlreadyRunning)
        ));
        drop(first);
    }

    #[test]
    fn redacts_local_user_paths() {
        let Some(local_app_data) = std::env::var_os("LOCALAPPDATA") else {
            return;
        };
        let value = format!("{}\\RCN-FPVSkyDive", local_app_data.to_string_lossy());
        assert_eq!(redact_text(&value), "%LOCALAPPDATA%\\RCN-FPVSkyDive");
    }
}
