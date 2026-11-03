"""Exercise the actual QML dependency gate with controlled process results."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1] / 'plugin/StartupCheck.qml'
with tempfile.TemporaryDirectory(prefix='openmouse-gate-') as directory:
    root = Path(directory)
    (root / 'Common').mkdir()
    (root / 'Common/qmldir').write_text('module qs.Common\nsingleton Proc 1.0 Proc.qml\n')
    shutil.copy(source, root / 'StartupCheck.qml')
    for output, code, allowed in [('v20.0.0', 0, True), ('v26.12.1', 0, True), ('v18.20.0', 0, False), ('', 127, False), ('garbage', 0, False)]:
        import json
        (root / 'Common/Proc.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    function runCommand(key, command, callback) {
        if (command.length !== 2 || command[0] !== "node" || command[1] !== "--version")
            throw new Error("Unexpected process command");
        callback(%s, %d);
    }
}
''' % (json.dumps(output), code))
        (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
    StartupCheck { id: gate }
    Timer { interval: 10; running: true; onTriggered: {
        gate.check(result => {
            console.warn((result === null) === %s ? "GATE_PASS" : "GATE_FAIL");
            Qt.quit();
        });
    } }
}
''' % str(allowed).lower())
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', XDG_RUNTIME_DIR=directory)
        result = subprocess.run(['quickshell', '-p', str(root)], env=env, capture_output=True, text=True, timeout=15)
        assert 'GATE_PASS' in result.stdout + result.stderr, result.stdout + result.stderr
        print(f'PASS version={output!r} exit={code} allowed={allowed}')
