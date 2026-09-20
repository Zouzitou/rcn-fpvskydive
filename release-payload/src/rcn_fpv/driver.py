from dataclasses import dataclass
from typing import Iterable

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
