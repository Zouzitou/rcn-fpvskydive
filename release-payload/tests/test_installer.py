from rcn_fpv.installer import InstallState, InstallerStateMachine

def test_ready_requires_every_gate():
    sm = InstallerStateMachine()
    sm.gates = type(sm.gates)(True, True, True, True, True, True, True, True)
    while sm.state not in (InstallState.READY, InstallState.FAILED): sm.advance()
    assert sm.state == InstallState.READY

def test_unverified_artifact_fails_closed():
    sm = InstallerStateMachine(); sm.advance(); sm.advance()
    assert sm.state == InstallState.FAILED
    assert "artifact" in sm.gates.failures[0]
