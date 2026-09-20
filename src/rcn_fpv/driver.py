from dataclasses import dataclass
from typing import Iterable
import re

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
    if not evidence.signed: reasons.append("driver is not signature-validated")
    if not evidence.ports_class: reasons.append("driver is not a Ports-class driver")
    if not any(required_vid.upper() in item and required_pid.upper() in item for item in ids):
        reasons.append("hardware ID does not match supported controller")
    return (not reasons, reasons)

def pnputil_command(inf_path):
    return ["pnputil.exe", "/add-driver", str(inf_path), "/install"]

def parse_driver_output(text: str):
    """Parse localized-ish pnputil output conservatively; unknown fields stay empty."""
    def field(label):
        match = re.search(rf"(?im)^\s*{re.escape(label)}\s*:\s*(.+?)\s*$", text)
        return match.group(1).strip() if match else ""
    ids = tuple(re.findall(r"(?i)USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}", text))
    return DriverEvidence(
        provider=field("Provider Name"), version=field("Driver Version"),
        signed=bool(re.search(r"(?i)signature|signed|digitally signed", text)),
        hardware_ids=ids, ports_class=bool(re.search(r"(?i)class\s*name\s*:\s*ports", text)),
    )
