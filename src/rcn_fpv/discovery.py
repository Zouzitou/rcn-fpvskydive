from dataclasses import dataclass
from typing import Iterable, Optional

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

def enumerate_protocol_ports():
    """Return pyserial ports enriched with USB/interface metadata when available."""
    try:
        from serial.tools import list_ports
    except ImportError:
        return []
    found = []
    for port in list_ports.comports():
        hwid = (port.hwid or "").upper()
        interface = next((part.split("_")[-1] for part in hwid.split() if part.startswith("MI_")), None)
        found.append(PortCandidate(
            device=port.device,
            description=port.description or "",
            vid=f"{port.vid:04X}" if port.vid is not None else None,
            pid=f"{port.pid:04X}" if port.pid is not None else None,
            interface=interface,
            instance_id=getattr(port, "serial_number", "") or getattr(port, "hwid", ""),
        ))
    return found
