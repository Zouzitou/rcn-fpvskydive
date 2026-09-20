from dataclasses import dataclass

@dataclass(frozen=True)
class StartupPlan:
    method: str
    command: str
    reason: str

def choose_startup_method(scheduled_task_available: bool, startup_folder_available: bool):
    if scheduled_task_available:
        return StartupPlan("scheduled-task", r"RCN-FPVSkyDive\Bridge", "verified per-user task available")
    if startup_folder_available:
        return StartupPlan("startup-folder", r"RCN-FPVSkyDive\Bridge.lnk", "scheduled task unavailable; using current-user fallback")
    return StartupPlan("none", "", "no safe per-user startup mechanism available")
