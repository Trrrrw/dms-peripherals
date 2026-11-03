"""Check cached status survives read failures and clears its warning on recovery."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix='openmouse-status-') as directory:
    root = Path(directory)
    shutil.copy(Path(__file__).resolve().parents[1] / 'plugin/MouseService.qml', root)
    (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
    QtObject {
        id: store
        property var value: null
        function savePluginState(id, key, data) { value = data; }
        function loadPluginState(id, key, fallback) { return value || fallback; }
    }
    MouseService { id: mouse; backendPath: ""; selectedDeviceId: "test"; stateStore: store }
    MouseService { id: restored; backendPath: ""; selectedDeviceId: "test"; stateStore: store }
    Timer { interval: 10; running: true; onTriggered: {
        mouse.fail("initial failure");
        let ok = mouse.status === null;
        mouse.receive(JSON.stringify({id: "status", result: {device_id: "test", battery_percent: 65}}));
        restored.restore();
        ok = ok && restored.status !== null && restored.status.battery_percent === 65 && restored.lastSuccess !== "" && restored.message.length > 0;
        mouse.fail("probe failed");
        ok = ok && mouse.status !== null && mouse.status.battery_percent === 65 && mouse.message === "probe failed";
        mouse.receive(JSON.stringify({id: "status", result: {device_id: "test", battery_percent: 64}}));
        ok = ok && mouse.status.battery_percent === 64 && mouse.message === "";
        restored.selectedDeviceId = "";
        restored.restore();
        ok = ok && restored.status === null;
        restored.selectedDeviceId = "another-device";
        ok = ok && restored.status === null;
        restored.receive(JSON.stringify({id: "status", result: {device_id: "test", battery_percent: 90}}));
        ok = ok && restored.status === null;
        console.warn(ok ? "STATUS_PASS" : "STATUS_FAIL");
        Qt.quit();
    } }
}
''')
    result = subprocess.run(['quickshell', '-p', directory], env=dict(os.environ, QT_QPA_PLATFORM='offscreen', XDG_RUNTIME_DIR=directory), capture_output=True, text=True, timeout=15)
    assert 'STATUS_PASS' in result.stdout + result.stderr, result.stdout + result.stderr
    print('PASS initial failure, cached status after failure, recovery')
