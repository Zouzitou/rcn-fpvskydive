mod mapping;
mod protocol;
mod tui;

use mapping::{MappingConfig, mode2_with_config};
use protocol::{drain_frames, enable_simulator, parse_sticks, read_sticks};
use std::{
    env, fs,
    io::{Read, Write},
    path::PathBuf,
    process::Command,
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};
use thiserror::Error;
use vigem_rust::{BusError, Client, ClientError, Ready, TargetHandle, X360Report, Xbox360};
use windows::Win32::Foundation::{CloseHandle, ERROR_ALREADY_EXISTS, GetLastError, HANDLE};
use windows::Win32::System::Threading::CreateMutexW;
use windows::core::HSTRING;

#[derive(Debug, Error)]
enum BridgeError {
    #[error(
        "usage: rcn-bridge status | diagnose [--redact] | tui | start | stop | repair | uninstall | open-fpv | game-check | self-test | verify-input [--port COM12] | watch | bridge-auto | probe --port COM12 | bridge --port COM12 | bridge-smoke --port COM12"
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

fn device_state_path() -> PathBuf {
    app_root().join("state").join("device.json")
}

fn verification_state_path() -> PathBuf {
    app_root().join("state").join("input-verification.json")
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
        "{{\"state\":\"{}\",\"port\":{},\"mapped_frames\":{},\"detail\":{},\"pid\":{},\"updated_unix\":{}}}",
        escape_json(state),
        port,
        mapped_frames,
        detail,
        std::process::id(),
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

fn persist_device_identity(port: &str) {
    let escaped_port = port.replace('\'', "''");
    let query = format!(
        "Get-CimInstance Win32_PnPEntity | Where-Object {{ $_.Status -eq 'OK' -and $_.PNPDeviceID -match 'VID_2CA3' -and $_.Name -match '\\({escaped_port}\\)' }} | Select-Object -First 1 | ForEach-Object {{ \"$($_.Name)|$($_.PNPDeviceID)\" }}"
    );
    let Ok(output) = run_powershell(&query) else {
        return;
    };
    let identity = output_text(output);
    let Some((name, instance_id)) = identity.split_once('|') else {
        return;
    };
    let path = device_state_path();
    let Some(parent) = path.parent() else { return };
    if fs::create_dir_all(parent).is_err() {
        return;
    }
    let json = format!(
        "{{\"port\":\"{}\",\"name\":\"{}\",\"instance_id\":\"{}\",\"updated_unix\":{}}}",
        escape_json(port),
        escape_json(name),
        escape_json(instance_id),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|time| time.as_secs())
            .unwrap_or(0)
    );
    let _ = fs::write(path, json);
}

fn json_string_field(contents: &str, field: &str) -> Option<String> {
    let marker = format!("\"{field}\":\"");
    let start = contents.find(&marker)? + marker.len();
    let bytes = contents.as_bytes();
    let mut index = start;
    let mut escaped = false;
    let mut value = String::new();
    while index < bytes.len() {
        let character = bytes[index] as char;
        if escaped {
            value.push(character);
            escaped = false;
        } else if character == '\\' {
            escaped = true;
        } else if character == '"' {
            return Some(value);
        } else {
            value.push(character);
        }
        index += 1;
    }
    None
}

fn normalize_instance_id(value: &str) -> String {
    let mut normalized = value.to_string();
    while normalized.contains("\\\\") {
        normalized = normalized.replace("\\\\", "\\");
    }
    normalized
}

fn json_number_field(contents: &str, field: &str) -> Option<u64> {
    let marker = format!("\"{field}\":");
    let start = contents.find(&marker)? + marker.len();
    let end = contents[start..]
        .find(|character: char| !character.is_ascii_digit())
        .map(|offset| start + offset)
        .unwrap_or(contents.len());
    contents[start..end].parse().ok()
}

fn diagnostic_category(
    interfaces: &str,
    protocol_port: Option<&str>,
    live_frames: &Result<Option<usize>, BridgeError>,
) -> &'static str {
    if protocol_port.is_none() {
        if interfaces.contains("For Debug") {
            "debug_only_close_assistant_and_reconnect"
        } else if interfaces.contains("VID_2CA3") {
            "device_seen_without_protocol_interface_check_vcom_driver_or_cable"
        } else {
            "controller_not_detected_check_power_data_cable_and_usb_port"
        }
    } else {
        match live_frames {
            Ok(Some(count)) if *count > 0 => "protocol_live_input_present_run_verify_input",
            Ok(_) => "protocol_interface_present_without_live_frames",
            Err(_) => "protocol_port_open_failed_check_busy_process_or_assistant",
        }
    }
}

fn current_device_instance_id() -> Option<String> {
    let contents = fs::read_to_string(device_state_path()).ok()?;
    json_string_field(&contents, "instance_id")
}

fn live_verification_valid(port: &str) -> bool {
    let Ok(contents) = fs::read_to_string(verification_state_path()) else {
        return false;
    };
    let Some(instance_id) = json_string_field(&contents, "instance_id") else {
        return false;
    };
    if json_string_field(&contents, "port").is_none() {
        return false;
    }
    let Some(verified_unix) = json_number_field(&contents, "verified_unix") else {
        return false;
    };
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|time| time.as_secs())
        .unwrap_or(0);
    let _ = port;
    let Some(current_instance_id) = current_device_instance_id() else {
        return false;
    };
    normalize_instance_id(&current_instance_id) == normalize_instance_id(&instance_id)
        && now.saturating_sub(verified_unix) <= 30 * 24 * 60 * 60
}

fn save_live_verification(port: &str, results: &[(&str, u16, u16, bool)]) {
    let Some(instance_id) = current_device_instance_id() else {
        return;
    };
    let path = verification_state_path();
    let Some(parent) = path.parent() else { return };
    if fs::create_dir_all(parent).is_err() {
        return;
    }
    let axes = results
        .iter()
        .map(|(name, minimum, maximum, _)| {
            format!(
                "{{\"name\":\"{}\",\"min\":{},\"max\":{}}}",
                escape_json(name),
                minimum,
                maximum
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    let verified_unix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|time| time.as_secs())
        .unwrap_or(0);
    let json = format!(
        "{{\"port\":\"{}\",\"instance_id\":\"{}\",\"verified_unix\":{},\"axes\":[{}]}}",
        escape_json(port),
        escape_json(&instance_id),
        verified_unix,
        axes
    );
    let _ = fs::write(path, json);
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
    let mut result = String::with_capacity(redacted.len());
    let mut offset = 0;
    while offset < redacted.len() {
        let bytes = redacted.as_bytes();
        let is_drive_path = offset + 2 < bytes.len()
            && bytes[offset].is_ascii_alphabetic()
            && bytes[offset + 1] == b':'
            && bytes[offset + 2] == b'\\';
        if is_drive_path {
            let path_end = redacted[offset..]
                .find(|character: char| matches!(character, '\r' | '\n' | '|' | '"'))
                .map(|index| offset + index)
                .unwrap_or(redacted.len());
            result.push_str("%REDACTED_PATH%");
            offset = path_end;
        } else {
            let character = redacted[offset..]
                .chars()
                .next()
                .expect("offset is always a valid UTF-8 boundary");
            result.push(character);
            offset += character.len_utf8();
        }
    }
    redacted = result;
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

#[derive(Default)]
struct ReconnectBackoff {
    consecutive_failures: u8,
}

impl ReconnectBackoff {
    const MAX_DELAY_SECONDS: u64 = 32;

    fn next_delay(&mut self) -> Duration {
        let exponent = self.consecutive_failures.min(5);
        self.consecutive_failures = self.consecutive_failures.saturating_add(1);
        Duration::from_secs((1_u64 << exponent).min(Self::MAX_DELAY_SECONDS))
    }

    fn reset(&mut self) {
        self.consecutive_failures = 0;
    }
}

fn acquire_watch_mutex() -> Result<WatchMutex, BridgeError> {
    acquire_watch_mutex_named("Global\\RCN-FPVSkyDive-Bridge")
}

fn acquire_watch_mutex_named(name: &str) -> Result<WatchMutex, BridgeError> {
    let name = HSTRING::from(name);
    let handle = unsafe { CreateMutexW(None, true, &name) }
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
        "$roots=@(); $keys=@('HKCU:\\Software\\Valve\\Steam','HKLM:\\SOFTWARE\\WOW6432Node\\Valve\\Steam','HKLM:\\SOFTWARE\\Valve\\Steam'); foreach($key in $keys){$item=Get-ItemProperty $key -ErrorAction SilentlyContinue; if($item.SteamPath){$roots+=$item.SteamPath}; if($item.InstallPath){$roots+=$item.InstallPath}; if($item.SteamExe){$roots+=(Split-Path $item.SteamExe)}}; Get-Process steam -ErrorAction SilentlyContinue | ForEach-Object { if($_.Path){$roots+=(Split-Path $_.Path)} }; $roots | Select-Object -Unique | ForEach-Object { $vdf=Join-Path $_ 'steamapps\\libraryfolders.vdf'; if(Test-Path $vdf){$roots += [regex]::Matches((Get-Content $vdf -Raw),'\"path\"\\s+\"([^\"]+)\"') | ForEach-Object {$_.Groups[1].Value}} }; $roots | Select-Object -Unique | ForEach-Object { foreach($name in @('FPV SkyDive','FPV.SkyDive')) { $p=Join-Path $_ (Join-Path 'steamapps\\common' $name); if(Test-Path $p){$p} } }",
    )?;
    let startup = fs::read_to_string(app_root().join("state").join("startup.json"))
        .unwrap_or_else(|_| "not_registered".to_string());
    let device =
        fs::read_to_string(device_state_path()).unwrap_or_else(|_| "not_persisted".to_string());
    let verification = fs::read_to_string(verification_state_path())
        .unwrap_or_else(|_| "not_verified".to_string());
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
    let category = diagnostic_category(&interfaces, protocol_port.as_deref(), &live_frames);
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
    println!("failure category: {category}");
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
    println!(
        "selected device: {}",
        if redact { redact_text(&device) } else { device }
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
    println!(
        "input verification: {}",
        if redact {
            redact_text(&verification)
        } else {
            verification
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
    let bootstrap = app_root().join("bootstrap.ps1");
    if !bootstrap.is_file() {
        return Err(BridgeError::Io(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "repair bootstrap is missing; rerun the one-line installer",
        )));
    }
    let output = Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
        .arg(bootstrap)
        .arg("-Repair")
        .output()?;
    std::io::stdout().write_all(&output.stdout)?;
    std::io::stderr().write_all(&output.stderr)?;
    if !output.status.success() {
        return Err(BridgeError::Io(std::io::Error::other(
            "verified repair reinstall failed",
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

fn open_fpv() -> Result<(), BridgeError> {
    let output = Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
        .arg(app_root().join("open-fpv.ps1"))
        .args(["-Action", "open"])
        .output()?;
    std::io::stdout().write_all(&output.stdout)?;
    std::io::stderr().write_all(&output.stderr)?;
    if !output.status.success() {
        return Err(BridgeError::Io(std::io::Error::other(
            "FPV SkyDive was not found in the detected Steam libraries",
        )));
    }
    Ok(())
}

fn game_check() -> Result<(), BridgeError> {
    let output = Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
        .arg(app_root().join("game-check.ps1"))
        .output()?;
    std::io::stdout().write_all(&output.stdout)?;
    std::io::stderr().write_all(&output.stderr)?;
    if !output.status.success() {
        return Err(BridgeError::Io(std::io::Error::other(
            "FPV SkyDive session verification failed",
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

fn verification_port_from_args() -> Result<String, BridgeError> {
    let mut args = env::args().skip(2);
    match args.next().as_deref() {
        None => discover_protocol_port().ok_or(BridgeError::NoProtocolPort),
        Some("--port") => args.next().ok_or(BridgeError::Usage),
        Some(_) => Err(BridgeError::Usage),
    }
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

fn sample_frame(
    serial: &mut dyn serialport::SerialPort,
    buffer: &mut Vec<u8>,
    chunk: &mut [u8],
) -> Result<Option<protocol::StickFrame>, BridgeError> {
    serial.write_all(&read_sticks())?;
    if let Ok(count) = serial.read(chunk) {
        buffer.extend_from_slice(&chunk[..count]);
    }
    Ok(drain_frames(buffer)
        .into_iter()
        .find_map(|packet| parse_sticks(&packet).ok()))
}

fn stick_axis(frame: protocol::StickFrame, index: usize) -> u16 {
    match index {
        0 => frame.left_h,
        1 => frame.left_v,
        2 => frame.right_h,
        _ => frame.right_v,
    }
}

fn verify_live_input(port: &str) -> Result<(), BridgeError> {
    persist_device_identity(port);
    let mut serial = connect(port)?;
    let mut buffer = Vec::new();
    let mut chunk = [0u8; 4096];
    let baseline_deadline = Instant::now() + Duration::from_secs(3);
    let baseline = loop {
        if let Some(frame) = sample_frame(&mut *serial, &mut buffer, &mut chunk)? {
            break frame;
        }
        if Instant::now() >= baseline_deadline {
            return Err(BridgeError::NoLiveFrames);
        }
        thread::sleep(Duration::from_millis(20));
    };
    println!("Quick stick check: move the requested stick, then press Enter.");
    let axes = [
        ("1 of 4 - left stick left and right", 0usize),
        ("2 of 4 - left stick up and down", 1usize),
        ("3 of 4 - right stick left and right", 2usize),
        ("4 of 4 - right stick up and down", 3usize),
    ];
    let mut results = Vec::new();
    for (name, axis_index) in axes {
        print!("{name}, then press Enter: ");
        std::io::stdout().flush()?;
        let mut minimum = stick_axis(baseline, axis_index);
        let mut maximum = minimum;
        let (entered_tx, entered_rx) = mpsc::channel();
        let input_thread = thread::spawn(move || {
            let mut response = String::new();
            let result = std::io::stdin().read_line(&mut response);
            let _ = entered_tx.send(result);
        });
        loop {
            if let Some(frame) = sample_frame(&mut *serial, &mut buffer, &mut chunk)? {
                let value = stick_axis(frame, axis_index);
                minimum = minimum.min(value);
                maximum = maximum.max(value);
            }
            if let Ok(result) = entered_rx.try_recv() {
                result?;
                break;
            }
            thread::sleep(Duration::from_millis(20));
        }
        input_thread
            .join()
            .map_err(|_| std::io::Error::other("input verification thread panicked"))?;
        let changed = maximum.saturating_sub(minimum) >= 100;
        results.push((name, minimum, maximum, changed));
    }
    let passed = results.iter().all(|(_, _, _, changed)| *changed);
    println!(
        "{{\"live_input_verification\":\"{}\",\"axes\":[",
        if passed { "passed" } else { "failed" }
    );
    for (index, (name, minimum, maximum, changed)) in results.iter().enumerate() {
        println!(
            "  {{\"name\":\"{}\",\"min\":{},\"max\":{},\"changed\":{}}}{}",
            name,
            minimum,
            maximum,
            changed,
            if index + 1 == results.len() { "" } else { "," }
        );
    }
    println!("]}}");
    if passed {
        save_live_verification(port, &results);
        Ok(())
    } else {
        Err(BridgeError::NoLiveFrames)
    }
}

fn protocol_port_from_name(name: &str) -> Option<String> {
    let normalized = name.to_ascii_lowercase();
    if !normalized.contains("for protocol") {
        return None;
    }
    let start = normalized.find("(com")? + 1;
    let end = name[start..].find(')')? + start;
    let port = name[start..end].trim();
    (port.len() > 3
        && port.starts_with("COM")
        && port[3..]
            .chars()
            .all(|character| character.is_ascii_digit()))
    .then(|| port.to_string())
}

fn rank_protocol_port(lines: &str) -> Option<String> {
    let mut candidates = lines
        .lines()
        .filter_map(|line| {
            let (name, instance_id) = line.split_once('|')?;
            let port = protocol_port_from_name(name)?;
            let port_number = port[3..].parse::<u32>().ok()?;
            Some((
                port_number,
                name.to_ascii_lowercase(),
                instance_id.to_ascii_lowercase(),
                port,
            ))
        })
        .collect::<Vec<_>>();
    candidates.sort_by(|left, right| {
        left.0
            .cmp(&right.0)
            .then(left.1.cmp(&right.1))
            .then(left.2.cmp(&right.2))
    });
    candidates.into_iter().next().map(|candidate| candidate.3)
}

fn discover_protocol_port() -> Option<String> {
    let query = "Get-CimInstance Win32_PnPEntity | Where-Object { $_.Status -eq 'OK' -and $_.PNPDeviceID -match 'VID_2CA3' } | ForEach-Object { \"$($_.Name)|$($_.PNPDeviceID)\" }";
    let output = Command::new("powershell.exe")
        .args(["-NoProfile", "-NonInteractive", "-Command", query])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    rank_protocol_port(&String::from_utf8_lossy(&output.stdout))
}

fn self_test_gamepad() -> Result<(), BridgeError> {
    let client = connect_vigem()?;
    let target = new_ready_target(&client)?;
    let pulse = X360Report {
        thumb_lx: 4_096,
        ..Default::default()
    };
    target.update(&pulse)?;
    target.update(&X360Report::default())?;
    println!("{{\"virtual_gamepad_test\":\"passed\",\"cleanup\":\"neutral update sent\"}}");
    Ok(())
}

fn connect_vigem() -> Result<Client, BridgeError> {
    let mut last_error = None;
    const MAX_ATTEMPTS: usize = 30;
    for attempt in 0..MAX_ATTEMPTS {
        match Client::connect() {
            Ok(client) => return Ok(client),
            Err(error @ ClientError::Bus(BusError::TargetNotReady { .. }))
                if attempt + 1 < MAX_ATTEMPTS =>
            {
                last_error = Some(error);
                thread::sleep(Duration::from_millis(200));
            }
            Err(error) => return Err(error.into()),
        }
    }
    Err(last_error
        .expect("retry loop must record the transient ViGEm connection error")
        .into())
}

fn new_ready_target(client: &Client) -> Result<TargetHandle<Xbox360, Ready>, BridgeError> {
    let mut last_error = None;
    const MAX_ATTEMPTS: usize = 30;
    for attempt in 0..MAX_ATTEMPTS {
        match client
            .new_x360_target()
            .plug()
            .and_then(|pending| pending.wait_for_ready())
        {
            Ok(target) => return Ok(target),
            Err(error @ ClientError::Bus(BusError::TargetNotReady { .. }))
                if attempt + 1 < MAX_ATTEMPTS =>
            {
                last_error = Some(error);
                thread::sleep(Duration::from_millis(200));
            }
            Err(error) => return Err(error.into()),
        }
    }
    Err(last_error
        .expect("retry loop must record the transient target error")
        .into())
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
    let client = connect_vigem()?;
    let target = new_ready_target(&client)?;
    let neutral = X360Report::default();
    target.update(&neutral)?;
    let mut mapped_frames = 0;
    let mut last_status = Instant::now();
    let bridge_result = (|| -> Result<usize, BridgeError> {
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
    })();
    let cleanup_result = target.update(&neutral);
    match (bridge_result, cleanup_result) {
        (Ok(mapped_frames), Ok(())) => Ok(mapped_frames),
        (Ok(_), Err(error)) => Err(error.into()),
        (Err(error), _) => Err(error),
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
    let mut reconnect_backoff = ReconnectBackoff::default();
    loop {
        let wait = match discover_protocol_port() {
            Some(port) => {
                persist_device_identity(&port);
                if !live_verification_valid(&port) {
                    reconnect_backoff.reset();
                    publish_status(
                        "awaiting_live_verification",
                        Some(&port),
                        0,
                        Some("run verify-input and move all four sticks"),
                    );
                    Duration::from_secs(1)
                } else {
                    publish_status("connecting", Some(&port), 0, None);
                    eprintln!("RCN bridge: using {port}");
                    match run_bridge(&port, None, mapping) {
                        Ok(_) => {
                            reconnect_backoff.reset();
                            Duration::from_secs(1)
                        }
                        Err(error) => {
                            let wait = reconnect_backoff.next_delay();
                            let detail = format!("{error}; retrying in {}s", wait.as_secs());
                            publish_status("waiting_for_controller", None, 0, Some(&detail));
                            eprintln!("RCN bridge: disconnected or unavailable: {detail}");
                            wait
                        }
                    }
                }
            }
            None => {
                reconnect_backoff.reset();
                publish_status("waiting_for_controller", None, 0, None);
                eprintln!("RCN bridge: waiting for a healthy DJI Protocol interface");
                Duration::from_secs(1)
            }
        };
        thread::sleep(wait);
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
    if command == "tui" {
        return tui::run();
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
    if command == "open-fpv" {
        return open_fpv();
    }
    if command == "game-check" {
        return game_check();
    }
    if command == "self-test" {
        return self_test_gamepad();
    }
    if command == "verify-input" {
        let port = verification_port_from_args()?;
        return verify_live_input(&port);
    }
    if command == "watch" {
        return watch();
    }
    if command == "bridge-auto" {
        let port = discover_protocol_port().ok_or(BridgeError::NoProtocolPort)?;
        persist_device_identity(&port);
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
    use super::{
        BridgeError, ReconnectBackoff, acquire_watch_mutex_named, diagnostic_category, escape_json,
        rank_protocol_port, redact_text,
    };

    #[test]
    fn escapes_status_text_for_json() {
        assert_eq!(escape_json("COM12 \"busy\""), "COM12 \\\"busy\\\"");
    }

    #[test]
    fn rejects_a_second_watcher_owner() {
        let name = format!("Global\\RCN-FPVSkyDive-Bridge-test-{}", std::process::id());
        let first = acquire_watch_mutex_named(&name).expect("first watcher owner");
        assert!(matches!(
            acquire_watch_mutex_named(&name),
            Err(BridgeError::AlreadyRunning)
        ));
        drop(first);
    }

    #[test]
    fn backs_off_reconnects_and_resets_after_a_healthy_state() {
        let mut backoff = ReconnectBackoff::default();
        let delays = (0..8)
            .map(|_| backoff.next_delay().as_secs())
            .collect::<Vec<_>>();
        assert_eq!(delays, vec![1, 2, 4, 8, 16, 32, 32, 32]);
        backoff.reset();
        assert_eq!(backoff.next_delay().as_secs(), 1);
    }

    #[test]
    fn redacts_local_user_paths() {
        let Some(local_app_data) = std::env::var_os("LOCALAPPDATA") else {
            return;
        };
        let value = format!("{}\\RCN-FPVSkyDive", local_app_data.to_string_lossy());
        assert_eq!(redact_text(&value), "%LOCALAPPDATA%\\RCN-FPVSkyDive");
    }

    #[test]
    fn redacts_non_profile_drive_paths() {
        assert_eq!(
            redact_text("path=Z:\\SteamLibrary\\steamapps\\common\\FPV.SkyDive|ready"),
            "path=%REDACTED_PATH%|ready"
        );
    }

    #[test]
    fn classifies_debug_only_and_live_protocol_states() {
        let no_live = Ok(Some(0));
        assert_eq!(
            diagnostic_category("OK|For Debug|VID_2CA3", None, &no_live),
            "debug_only_close_assistant_and_reconnect"
        );
        let live = Ok(Some(3));
        assert_eq!(
            diagnostic_category("OK|For Protocol|VID_2CA3", Some("COM12"), &live),
            "protocol_live_input_present_run_verify_input"
        );
    }

    #[test]
    fn ranks_only_protocol_ports_without_hard_coding_a_com_number() {
        let interfaces = concat!(
            "DEVICE USB VCOM For Debug (COM11)|USB\\VID_2CA3&PID_1020&MI_04\n",
            "DEVICE USB VCOM For Protocol (COM12)|USB\\VID_2CA3&PID_1020&MI_02\n",
            "DEVICE USB VCOM For Protocol (COM3)|USB\\VID_2CA3&PID_1020&MI_12\n",
        );
        assert_eq!(rank_protocol_port(interfaces), Some("COM3".to_string()));
        assert_eq!(
            rank_protocol_port("DEVICE USB VCOM For Debug (COM19)|USB\\VID_2CA3"),
            None
        );
    }
}
