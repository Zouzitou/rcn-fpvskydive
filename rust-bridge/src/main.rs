mod mapping;
mod protocol;

use mapping::mode2;
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
        "usage: rcn-bridge status | diagnose | start | stop | repair | uninstall | self-test | watch | bridge-auto | probe --port COM12 | bridge --port COM12 | bridge-smoke --port COM12"
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

fn diagnose() -> Result<(), BridgeError> {
    let status = fs::read_to_string(status_path())
        .unwrap_or_else(|_| "{\"state\":\"not_started\"}".to_string());
    let output = run_powershell(
        "Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPDeviceID -match 'VID_2CA3' -or $_.Name -match 'DJI USB' } | ForEach-Object { \"$($_.Status)|$($_.Name)|$($_.PNPDeviceID)\" }",
    )?;
    println!("status: {status}");
    println!("runtime: native-rust");
    println!("interfaces:");
    let interfaces = String::from_utf8_lossy(&output.stdout);
    if interfaces.trim().is_empty() {
        println!("  none");
    } else {
        for line in interfaces.lines() {
            println!("  {line}");
        }
    }
    println!(
        "log: {}",
        app_root().join("logs").join("bridge.log").display()
    );
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

fn run_bridge(port: &str, duration: Option<Duration>) -> Result<usize, BridgeError> {
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
                let axes = mode2(frame);
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
    loop {
        match discover_protocol_port() {
            Some(port) => {
                publish_status("connecting", Some(&port), 0, None);
                eprintln!("RCN bridge: using {port}");
                if let Err(error) = run_bridge(&port, None) {
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
        return diagnose();
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
        run_bridge(&port, None)?;
        return Ok(());
    }
    let port = port_from_args()?;
    if command == "probe" {
        let mut serial = connect(&port)?;
        let mut buffer = Vec::new();
        let mut chunk = [0u8; 4096];
        for _ in 0..12 {
            serial.write_all(&read_sticks())?;
            thread::sleep(Duration::from_millis(60));
            if let Ok(count) = serial.read(&mut chunk) {
                buffer.extend_from_slice(&chunk[..count]);
            }
        }
        let frames = drain_frames(&mut buffer);
        let sticks = frames
            .iter()
            .filter_map(|frame| parse_sticks(frame).ok())
            .count();
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
    use super::escape_json;

    #[test]
    fn escapes_status_text_for_json() {
        assert_eq!(escape_json("COM12 \"busy\""), "COM12 \\\"busy\\\"");
    }
}
