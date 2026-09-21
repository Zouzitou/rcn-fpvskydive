from dataclasses import dataclass
from pathlib import Path
import json, re, subprocess

class DriverInstallError(RuntimeError): pass

@dataclass(frozen=True)
class DriverEvidence:
    provider: str
    version: str
    signed: bool
    hardware_ids: tuple[str, ...]
    ports_class: bool

def validate_driver(evidence: DriverEvidence, required_vid="2CA3", required_pid="1020"):
    """Fail closed unless the package is signed, Ports-class, and matches the device."""
    ids = {x.upper().replace("&", "") for x in evidence.hardware_ids}
    target = f"USBVID_{required_vid.upper()}PID_{required_pid.upper()}"
    reasons = []
    if "dji" not in evidence.provider.casefold(): reasons.append("driver provider is not DJI")
    if not evidence.signed: reasons.append("driver is not signature-validated")
    if not evidence.ports_class: reasons.append("driver is not a Ports-class driver")
    if not any(required_vid.upper() in item and required_pid.upper() in item for item in ids):
        reasons.append("hardware ID does not match supported controller")
    return (not reasons, reasons)

def pnputil_command(inf_path):
    return ["pnputil.exe", "/add-driver", str(inf_path), "/install"]

def managed_inf(root: Path, inf_path):
    """Accept an INF only from the per-user managed driver payload directory."""
    if inf_path is None:
        raise DriverInstallError("driver INF must be supplied with --inf")
    driver_root = (Path(root) / "drivers").resolve()
    candidate = Path(inf_path).expanduser().resolve()
    if candidate.suffix.lower() != ".inf" or not candidate.is_file() or not candidate.is_relative_to(driver_root):
        raise DriverInstallError("driver INF must be an existing .inf file inside the managed drivers folder")
    return candidate

def driver_install_command(inf_path):
    """Return the UAC-elevated, wait-for-completion PowerShell invocation."""
    escaped = str(inf_path).replace("'", "''")
    script = "$p=Start-Process -FilePath 'pnputil.exe' -ArgumentList @('/add-driver','%s','/install') -Wait -PassThru -Verb RunAs; exit $p.ExitCode" % escaped
    return ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script]

def install_managed_driver(root: Path, inf_path, runner=subprocess.run):
    """Install a deliberately supplied DJI package, then prove the active driver passes validation."""
    inf = managed_inf(root, inf_path)
    result = runner(driver_install_command(inf), check=False)
    if result.returncode:
        raise DriverInstallError("driver installation was cancelled or pnputil failed")
    evidence = discover_driver_evidence()
    valid, reasons = validate_driver(evidence) if evidence else (False, ["no installed DJI Ports driver was found after installation"])
    if not valid:
        raise DriverInstallError("installed driver did not pass verification: " + "; ".join(reasons))
    return evidence

def parse_driver_output(text: str):
    """Parse localized-ish pnputil output conservatively; unknown fields stay empty."""
    def field(label):
        match = re.search(rf"(?im)^\s*{re.escape(label)}\s*:\s*(.+?)\s*$", text)
        return match.group(1).strip() if match else ""
    ids = tuple(re.findall(r"(?i)USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}", text))
    return DriverEvidence(
        provider=field("Provider Name"), version=field("Driver Version"),
        signed=bool(re.search(r"(?im)^\s*(?:digitally\s+signed|signed)\s*:\s*(?:yes|true)\b", text)),
        hardware_ids=ids, ports_class=bool(re.search(r"(?i)class\s*name\s*:\s*ports", text)),
    )

def discover_driver_evidence():
    """Read signed-driver evidence for the supported DJI USB hardware through CIM."""
    script = (
        "$d=Get-CimInstance Win32_PnPSignedDriver | Where-Object {$_.DeviceID -match 'VID_2CA3&PID_1020'} | "
        "Select-Object Manufacturer,DriverVersion,IsSigned,DeviceClass,DeviceID; $d | ConvertTo-Json -Compress"
    )
    try:
        result = subprocess.run(["powershell.exe", "-NoProfile", "-Command", script], capture_output=True, text=True, check=False)
        if result.returncode or not result.stdout.strip(): return None
        records = json.loads(result.stdout)
        records = records if isinstance(records, list) else [records]
        records = [record for record in records if isinstance(record, dict)]
        if not records: return None
        record = records[0]
        return DriverEvidence(
            provider=str(record.get("Manufacturer") or ""), version=str(record.get("DriverVersion") or ""),
            signed=record.get("IsSigned") is True, hardware_ids=tuple(str(item.get("DeviceID") or "") for item in records),
            ports_class=str(record.get("DeviceClass") or "").lower() == "ports",
        )
    except (OSError, ValueError, TypeError):
        return None
