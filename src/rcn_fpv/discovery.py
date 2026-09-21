from dataclasses import dataclass
from typing import Iterable, Optional
import json
import re
import subprocess

SUPPORTED = {"RC-N1": {("2CA3", "1020")}}
DJI_VENDOR_ID = "2CA3"

@dataclass(frozen=True)
class PortCandidate:
    device: str
    description: str
    vid: Optional[str] = None
    pid: Optional[str] = None
    interface: Optional[str] = None
    instance_id: str = ""
    controller: Optional[str] = None

    @property
    def is_protocol(self):
        return "for protocol" in self.description.lower() or (self.interface or "").upper() == "MI_02"

    @property
    def is_debug(self):
        return "for debug" in self.description.lower() or (self.interface or "").upper() == "MI_04"

    @property
    def supported_usb(self):
        return (self.vid or "").upper() == DJI_VENDOR_ID and self.is_protocol and not self.is_debug

    @property
    def proven_model(self):
        identity = ((self.vid or "").upper(), (self.pid or "").upper())
        return next((model for model, identities in SUPPORTED.items() if identity in identities), None)

def rank_candidates(candidates: Iterable[PortCandidate]):
    valid = [c for c in candidates if c.supported_usb and c.is_protocol and not c.is_debug]
    return sorted(valid, key=lambda c: (c.proven_model is None, c.controller or "ZZZ", c.description.lower(), c.device.lower(), c.instance_id.lower()))

def choose_candidate(candidates: Iterable[PortCandidate]):
    ranked = rank_candidates(candidates)
    return ranked[0] if ranked else None

def classify_usb(vid, pid):
    identity = ((vid or "").upper(), (pid or "").upper())
    for model, identities in SUPPORTED.items():
        if identity in identities: return {"model": model, "status": "supported"}
    if identity[0] == DJI_VENDOR_ID:
        return {"model": "RC-N family unconfirmed", "status": "requires Protocol port and live input verification"}
    return {"model": None, "status": "unknown device"}

def parse_pnp_serial_records(text):
    """Return Windows PnP serial records keyed by COM name, without trusting display names."""
    try:
        records = json.loads(text)
    except (TypeError, ValueError):
        return {}
    records = records if isinstance(records, list) else [records]
    result = {}
    for record in records:
        if not isinstance(record, dict): continue
        device = str(record.get("DeviceID") or "").upper()
        instance = str(record.get("PNPDeviceID") or "")
        if re.fullmatch(r"COM\d+", device) and instance:
            result[device] = {"instance_id": instance, "description": str(record.get("Name") or ""),
                              "status": str(record.get("Status") or "")}
    return result

def pnp_serial_records():
    script = "$d=Get-CimInstance Win32_SerialPort | Select-Object DeviceID,Name,PNPDeviceID,Status; $d | ConvertTo-Json -Compress"
    try:
        result = subprocess.run(["powershell.exe", "-NoProfile", "-Command", script], capture_output=True, text=True, check=False)
        return parse_pnp_serial_records(result.stdout) if result.returncode == 0 else {}
    except OSError:
        return {}

def enumerate_protocol_ports():
    """Return pyserial ports enriched with USB/interface metadata when available."""
    try:
        from serial.tools import list_ports
    except ImportError:
        return []
    pnp = pnp_serial_records()
    found = []
    for port in list_ports.comports():
        hwid = (port.hwid or "").upper()
        interface = next((part.split("_")[-1] for part in hwid.split() if part.startswith("MI_")), None)
        record = pnp.get(port.device.upper(), {})
        instance = record.get("instance_id") or getattr(port, "serial_number", "") or getattr(port, "hwid", "")
        pnp_hwid = instance.upper()
        if not interface:
            match = re.search(r"MI_(\d{2})", pnp_hwid)
            interface = match.group(1) if match else None
        vid_match = re.search(r"VID_([0-9A-F]{4})", pnp_hwid)
        pid_match = re.search(r"PID_([0-9A-F]{4})", pnp_hwid)
        found.append(PortCandidate(
            device=port.device,
            description=record.get("description") or port.description or "",
            vid=f"{port.vid:04X}" if port.vid is not None else (vid_match.group(1) if vid_match else None),
            pid=f"{port.pid:04X}" if port.pid is not None else (pid_match.group(1) if pid_match else None),
            interface=interface,
            instance_id=instance,
        ))
    return found
