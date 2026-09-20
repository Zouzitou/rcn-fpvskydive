from dataclasses import dataclass
from typing import Iterable, Optional

SUPPORTED = {"RC-N1": {("2CA3", "1020")}, "RC-N2": set(), "RC-N3": set()}

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
        return ((self.vid or "").upper(), (self.pid or "").upper()) in {
            pair for pairs in SUPPORTED.values() for pair in pairs
        }

def rank_candidates(candidates: Iterable[PortCandidate]):
    valid = [c for c in candidates if c.supported_usb and c.is_protocol and not c.is_debug]
    return sorted(valid, key=lambda c: (c.controller or "ZZZ", c.description.lower(), c.device.lower(), c.instance_id.lower()))

def choose_candidate(candidates: Iterable[PortCandidate]):
    ranked = rank_candidates(candidates)
    return ranked[0] if ranked else None

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
